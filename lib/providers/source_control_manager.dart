import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:fedit/models/git_models.dart';
import 'package:fedit/services/git_service.dart';

/// Workspace Version Manager (Source Control State Manager).
///
/// Implements full VS Code Source Control capabilities:
/// - Staged Changes, Working Tree Changes, Untracked, Merge Conflicts
/// - Branch switching, creating, deleting, and tracking
/// - Sync Changes (ahead / behind), Fetch, Pull, Push
/// - Discard Changes (revert file to HEAD or delete untracked)
/// - Commit (staged or all), Amend
/// - Stash management (save, pop, apply, drop)
/// - Tag management
/// - Background execution preventing UI freezing or crashes
class SourceControlManager extends ChangeNotifier {
  SourceControlManager({
    GitService? gitService,
    String? initialWorkspacePath,
  }) : _git = gitService ?? const GitService() {
    if (initialWorkspacePath != null && initialWorkspacePath.isNotEmpty) {
      openWorkspace(initialWorkspacePath);
    }
  }

  final GitService _git;

  // Workspace state
  String? _workspacePath;
  String? _repoRootPath;
  bool _isRepo = false;
  bool _isInitialized = false;

  // SCM State
  GitWorkspaceStatus _status = GitWorkspaceStatus.empty;
  List<GitBranchData> _branches = const [];
  List<GitRemote> _remotes = const [];
  List<GitStashData> _stashes = const [];
  List<GitTagData> _tags = const [];
  List<GitCommitSummary> _recentCommits = const [];

  // Operation state
  bool _isBusy = false;
  String? _busyMessage;
  String? _lastError;
  final List<GitOperationEvent> _events = [];

  // Commit input
  final TextEditingController commitMessageController = TextEditingController();

  // Credentials and Author
  AuthSpec _authSpec = const AuthSpec.none();
  GitAuthor _author = GitAuthor.defaultAuthor;

  // Real-time File System Watcher
  StreamSubscription<FileSystemEvent>? _watcherSub;
  Timer? _debounceTimer;

  // Getters
  GitService get gitService => _git;
  String? get workspacePath => _workspacePath;
  String? get repoRootPath => _repoRootPath;
  bool get isRepo => _isRepo;
  bool get isInitialized => _isInitialized;
  GitWorkspaceStatus get status => _status;
  List<GitBranchData> get branches => List.unmodifiable(_branches);
  List<GitRemote> get remotes => List.unmodifiable(_remotes);
  List<GitStashData> get stashes => List.unmodifiable(_stashes);
  List<GitTagData> get tags => List.unmodifiable(_tags);
  List<GitCommitSummary> get recentCommits => List.unmodifiable(_recentCommits);

  List<GitFileStatus> get stagedChanges => _status.stagedChanges;
  List<GitFileStatus> get workingTreeChanges => _status.workingTreeChanges;
  List<GitFileStatus> get untrackedChanges => _status.untrackedChanges;
  List<GitFileStatus> get mergeConflicts => _status.mergeConflicts;

  String? get currentBranch => _status.currentBranch;
  String? get headSha => _status.headSha;
  int get aheadCount => _status.aheadCount;
  int get behindCount => _status.behindCount;
  bool get isClean => _status.isClean;
  bool get isMerging => _status.isMerging;
  bool get isBusy => _isBusy;
  String? get busyMessage => _busyMessage;
  String? get lastError => _lastError;
  List<GitOperationEvent> get events => List.unmodifiable(_events);
  AuthSpec get authSpec => _authSpec;
  GitAuthor get author => _author;

  void setAuthSpec(AuthSpec spec) {
    _authSpec = spec;
    notifyListeners();
  }

  void setAuthor(GitAuthor author) {
    _author = author;
    notifyListeners();
  }

  // ===========================================================================
  // Workspace Lifecycle
  // ===========================================================================

  /// Opens and binds to a workspace directory path.
  Future<void> openWorkspace(String path) async {
    _workspacePath = path.replaceAll(r'\', '/');
    _isInitialized = true;
    _lastError = null;
    notifyListeners();

    _startWatcher();
    await _detectAndRefresh();
  }

  void _startWatcher() {
    _stopWatcher();
    final path = _workspacePath;
    if (path == null) return;
    final dir = Directory(path);
    if (!dir.existsSync()) return;

    try {
      _watcherSub = dir.watch(recursive: true).listen((event) {
        final p = event.path.replaceAll(r'\', '/');
        // Ignore git internals unless index or refs changed
        if (p.contains('/.git/')) {
          if (!p.endsWith('/.git/index') &&
              !p.endsWith('/.git/HEAD') &&
              !p.contains('/.git/refs/')) {
            return;
          }
        }
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 300), () {
          if (_repoRootPath != null && !_isBusy) {
            _refreshStatusOnly();
          }
        });
      });
    } catch (_) {
      // Watching not supported or permission denied on some systems
    }
  }

  void _stopWatcher() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _watcherSub?.cancel();
    _watcherSub = null;
  }

  /// Initializes a new repository in current workspace.
  Future<void> initRepository({String initialHead = 'main'}) async {
    final root = _workspacePath;
    if (root == null) throw StateError('No workspace currently opened.');

    await _runAction('Initializing repository', () async {
      await _git.initRepository(
        path: root,
        initialHead: initialHead,
        author: _author,
      );
      _events.add(GitOperationEvent.info('Initialized repository at $root'));
      await _detectAndRefresh();
    });
  }

  /// Refreshes the repository status and metadata.
  Future<void> refresh() async {
    if (_repoRootPath == null) {
      await _detectAndRefresh();
      return;
    }
    await _refreshStatusOnly();
  }

  Future<void> _detectAndRefresh() async {
    final path = _workspacePath;
    if (path == null) return;

    final repoRoot = await _git.findRepositoryRoot(path);
    _repoRootPath = repoRoot;
    _isRepo = repoRoot != null;

    if (_isRepo && repoRoot != null) {
      await _refreshStatusOnly();
    } else {
      _status = GitWorkspaceStatus.empty;
      _branches = const [];
      _remotes = const [];
      _stashes = const [];
      _tags = const [];
      _recentCommits = const [];
      notifyListeners();
    }
  }

  Future<void> _refreshStatusOnly() async {
    final repoPath = _repoRootPath;
    if (repoPath == null) return;

    try {
      final newStatus = await _git.getStatus(repoPath);
      final newBranches = await _git.getBranches(repoPath);
      final newRemotes = await _git.getRemotes(repoPath);
      final newStashes = await _git.getStashes(repoPath);
      final newTags = await _git.getTags(repoPath);
      final newCommits = await _git.getCommits(repoPath, limit: 30);

      _status = newStatus;
      _branches = newBranches;
      _remotes = newRemotes;
      _stashes = newStashes;
      _tags = newTags;
      _recentCommits = newCommits;
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      _events.add(GitOperationEvent.error('Failed to refresh Git status', e.toString()));
    } finally {
      notifyListeners();
    }
  }

  // ===========================================================================
  // Staging & Unstaging
  // ===========================================================================

  /// Stages a single file (`git add <file>`).
  Future<void> stage(String relativePath) async {
    final repo = _requireRepo();
    await _runAction('Staging $relativePath', () async {
      await _git.stageFile(repo, relativePath);
      _events.add(GitOperationEvent.info('Staged $relativePath'));
      await _refreshStatusOnly();
    });
  }

  /// Stages multiple files.
  Future<void> stageMultiple(List<String> relativePaths) async {
    final repo = _requireRepo();
    await _runAction('Staging ${relativePaths.length} files', () async {
      await _git.stageFiles(repo, relativePaths);
      _events.add(GitOperationEvent.info('Staged ${relativePaths.length} files'));
      await _refreshStatusOnly();
    });
  }

  /// Stages all changes (`git add -A`).
  Future<void> stageAll() async {
    final repo = _requireRepo();
    await _runAction('Staging all changes', () async {
      await _git.stageAll(repo);
      _events.add(GitOperationEvent.info('Staged all changes'));
      await _refreshStatusOnly();
    });
  }

  /// Unstages a single file (`git restore --staged <file>`).
  Future<void> unstage(String relativePath) async {
    final repo = _requireRepo();
    await _runAction('Unstaging $relativePath', () async {
      await _git.unstageFile(repo, relativePath);
      _events.add(GitOperationEvent.info('Unstaged $relativePath'));
      await _refreshStatusOnly();
    });
  }

  /// Unstages multiple files.
  Future<void> unstageMultiple(List<String> relativePaths) async {
    final repo = _requireRepo();
    await _runAction('Unstaging ${relativePaths.length} files', () async {
      await _git.unstageFiles(repo, relativePaths);
      _events.add(GitOperationEvent.info('Unstaged ${relativePaths.length} files'));
      await _refreshStatusOnly();
    });
  }

  /// Unstages all staged changes (`git restore --staged .`).
  Future<void> unstageAll() async {
    final repo = _requireRepo();
    await _runAction('Unstaging all changes', () async {
      await _git.unstageAll(repo);
      _events.add(GitOperationEvent.info('Unstaged all changes'));
      await _refreshStatusOnly();
    });
  }

  // ===========================================================================
  // Discard Changes (VS Code "Discard Changes")
  // ===========================================================================

  /// Discards changes in a single file.
  Future<void> discard(String relativePath) async {
    final repo = _requireRepo();
    await _runAction('Discarding changes in $relativePath', () async {
      await _git.discardFile(repo, relativePath);
      _events.add(GitOperationEvent.info('Discarded changes in $relativePath'));
      await _refreshStatusOnly();
    });
  }

  /// Discards changes in multiple files.
  Future<void> discardMultiple(List<String> relativePaths) async {
    final repo = _requireRepo();
    await _runAction('Discarding changes in ${relativePaths.length} files', () async {
      await _git.discardFiles(repo, relativePaths);
      _events.add(GitOperationEvent.info('Discarded changes in ${relativePaths.length} files'));
      await _refreshStatusOnly();
    });
  }

  /// Discards all working tree changes and untracked files.
  Future<void> discardAll() async {
    final repo = _requireRepo();
    await _runAction('Discarding all changes', () async {
      await _git.discardAll(repo);
      _events.add(GitOperationEvent.info('Discarded all changes'));
      await _refreshStatusOnly();
    });
  }

  // ===========================================================================
  // Commits & History
  // ===========================================================================

  /// Commits staged changes or all changes if [stageAllBeforeCommit] is set.
  Future<void> commit({
    String? message,
    bool stageAllBeforeCommit = false,
  }) async {
    final repo = _requireRepo();
    final commitMsg = (message ?? commitMessageController.text).trim();
    if (commitMsg.isEmpty) {
      throw ArgumentError('Commit message cannot be empty.');
    }

    if (!stageAllBeforeCommit && stagedChanges.isEmpty && (workingTreeChanges.isNotEmpty || untrackedChanges.isNotEmpty)) {
      stageAllBeforeCommit = true;
    }

    await _runAction('Committing changes', () async {
      final sha = await _git.commit(
        repo,
        message: commitMsg,
        author: _author,
        stageAllBeforeCommit: stageAllBeforeCommit,
      );
      commitMessageController.clear();
      _events.add(GitOperationEvent.info('Committed', sha.substring(0, 7)));
      await _refreshStatusOnly();
    });
  }

  /// Amends the last commit.
  Future<void> commitAmend({String? message}) async {
    final repo = _requireRepo();
    final commitMsg = (message ?? commitMessageController.text).trim();
    if (commitMsg.isEmpty) {
      throw ArgumentError('Commit message cannot be empty.');
    }

    await _runAction('Amending commit', () async {
      final sha = await _git.commit(
        repo,
        message: commitMsg,
        author: _author,
        amend: true,
      );
      commitMessageController.clear();
      _events.add(GitOperationEvent.info('Amended commit', sha.substring(0, 7)));
      await _refreshStatusOnly();
    });
  }

  /// Undoes the last commit on the current branch (soft or mixed reset).
  Future<void> undoCommit({bool soft = true}) async {
    final repo = _requireRepo();
    await _runAction('Undoing last commit', () async {
      await _git.undoCommit(repo, soft: soft);
      _events.add(GitOperationEvent.info('Undid last commit'));
      await _refreshStatusOnly();
    });
  }

  /// Commits changes and immediately pushes to remote.
  Future<void> commitAndPush({String? message}) async {
    await commit(message: message);
    await push();
  }

  /// Commits changes and immediately syncs with remote.
  Future<void> commitAndSync({String? message}) async {
    await commit(message: message);
    await sync();
  }

  // ===========================================================================
  // Branches
  // ===========================================================================

  /// Switches / checkouts a branch.
  Future<void> switchBranch(String branchName) async {
    final repo = _requireRepo();
    await _runAction('Switching to branch $branchName', () async {
      await _git.checkout(repo, branchOrRef: branchName);
      _events.add(GitOperationEvent.info('Switched to branch $branchName'));
      await _refreshStatusOnly();
    });
  }

  /// Creates a new branch, optionally checking it out.
  Future<void> createBranch(String branchName, {bool checkout = true}) async {
    final repo = _requireRepo();
    await _runAction('Creating branch $branchName', () async {
      await _git.createBranch(repo, name: branchName, checkout: checkout);
      _events.add(GitOperationEvent.info('Created branch $branchName'));
      await _refreshStatusOnly();
    });
  }

  /// Deletes a branch.
  Future<void> deleteBranch(String branchName, {bool force = false}) async {
    final repo = _requireRepo();
    await _runAction('Deleting branch $branchName', () async {
      await _git.deleteBranch(repo, name: branchName, force: force);
      _events.add(GitOperationEvent.info('Deleted branch $branchName'));
      await _refreshStatusOnly();
    });
  }

  // ===========================================================================
  // Remote Synchronization (VS Code "Sync Changes" button, Fetch, Pull, Push)
  // ===========================================================================

  /// Synchronizes changes with remote upstream branch (pulls then pushes).
  Future<void> sync() async {
    final repo = _requireRepo();
    await _runAction('Synchronizing with remote', () async {
      if (behindCount > 0) {
        await _git.pull(repo, authSpec: _authSpec, author: _author);
        _events.add(GitOperationEvent.info('Pulled $behindCount commit(s)'));
      }
      if (aheadCount > 0) {
        await _git.push(repo, authSpec: _authSpec);
        _events.add(GitOperationEvent.info('Pushed $aheadCount commit(s)'));
      }
      if (behindCount == 0 && aheadCount == 0) {
        await _git.fetch(repo, authSpec: _authSpec);
        _events.add(GitOperationEvent.info('Fetched latest updates from remote'));
      }
      await _refreshStatusOnly();
    });
  }

  /// Fetches latest commits from remote (`git fetch`).
  Future<void> fetch({String remote = 'origin'}) async {
    final repo = _requireRepo();
    await _runAction('Fetching from $remote', () async {
      await _git.fetch(repo, remote: remote, authSpec: _authSpec);
      _events.add(GitOperationEvent.info('Fetched from $remote'));
      await _refreshStatusOnly();
    });
  }

  /// Pulls commits from remote (`git pull`).
  Future<void> pull({String remote = 'origin', String? branch}) async {
    final repo = _requireRepo();
    await _runAction('Pulling from $remote', () async {
      await _git.pull(
        repo,
        remote: remote,
        branch: branch,
        authSpec: _authSpec,
        author: _author,
      );
      _events.add(GitOperationEvent.info('Pulled from $remote'));
      await _refreshStatusOnly();
    });
  }

  /// Pushes commits to remote (`git push`).
  Future<void> push({
    String remote = 'origin',
    String? branch,
    bool setUpstream = false,
  }) async {
    final repo = _requireRepo();
    await _runAction('Pushing to $remote', () async {
      await _git.push(
        repo,
        remote: remote,
        branch: branch,
        setUpstream: setUpstream,
        authSpec: _authSpec,
      );
      _events.add(GitOperationEvent.info('Pushed to $remote'));
      await _refreshStatusOnly();
    });
  }

  // ===========================================================================
  // Stash
  // ===========================================================================

  /// Saves current changes to stash.
  Future<void> saveStash({String? message, bool includeUntracked = false}) async {
    final repo = _requireRepo();
    await _runAction('Saving stash', () async {
      final sha = await _git.saveStash(
        repo,
        message: message,
        includeUntracked: includeUntracked,
        author: _author,
      );
      _events.add(GitOperationEvent.info('Saved stash', sha.substring(0, 7)));
      await _refreshStatusOnly();
    });
  }

  /// Pops stash at [index].
  Future<void> popStash([int index = 0]) async {
    final repo = _requireRepo();
    await _runAction('Popping stash #$index', () async {
      await _git.popStash(repo, index: index);
      _events.add(GitOperationEvent.info('Popped stash #$index'));
      await _refreshStatusOnly();
    });
  }

  /// Applies stash at [index].
  Future<void> applyStash([int index = 0]) async {
    final repo = _requireRepo();
    await _runAction('Applying stash #$index', () async {
      await _git.applyStash(repo, index: index);
      _events.add(GitOperationEvent.info('Applied stash #$index'));
      await _refreshStatusOnly();
    });
  }

  /// Drops stash at [index].
  Future<void> dropStash([int index = 0]) async {
    final repo = _requireRepo();
    await _runAction('Dropping stash #$index', () async {
      await _git.dropStash(repo, index: index);
      _events.add(GitOperationEvent.info('Dropped stash #$index'));
      await _refreshStatusOnly();
    });
  }

  // ===========================================================================
  // Remotes & Rebase
  // ===========================================================================

  /// Adds a new remote repository reference.
  Future<void> addRemote({required String name, required String url}) async {
    final repo = _requireRepo();
    await _runAction('Adding remote $name', () async {
      await _git.addRemote(repo, name: name, url: url);
      _events.add(GitOperationEvent.info('Added remote $name ($url)'));
      await _refreshStatusOnly();
    });
  }

  /// Removes an existing remote repository reference.
  Future<void> removeRemote({required String name}) async {
    final repo = _requireRepo();
    await _runAction('Removing remote $name', () async {
      await _git.removeRemote(repo, name: name);
      _events.add(GitOperationEvent.info('Removed remote $name'));
      await _refreshStatusOnly();
    });
  }

  /// Updates URL of an existing remote.
  Future<void> setRemoteUrl({required String name, required String url}) async {
    final repo = _requireRepo();
    await _runAction('Updating remote $name URL', () async {
      await _git.setRemoteUrl(repo, name: name, url: url);
      _events.add(GitOperationEvent.info('Updated remote $name URL'));
      await _refreshStatusOnly();
    });
  }

  /// Rebases the current branch onto [upstreamBranch].
  Future<void> rebase({required String upstreamBranch}) async {
    final repo = _requireRepo();
    await _runAction('Rebasing onto $upstreamBranch', () async {
      await _git.rebase(repo, upstreamBranch: upstreamBranch, author: _author);
      _events.add(GitOperationEvent.info('Rebased onto $upstreamBranch'));
      await _refreshStatusOnly();
    });
  }

  /// Aborts an in-progress rebase operation.
  Future<void> abortRebase() async {
    final repo = _requireRepo();
    await _runAction('Aborting rebase', () async {
      await _git.abortRebase(repo);
      _events.add(GitOperationEvent.info('Aborted rebase'));
      await _refreshStatusOnly();
    });
  }

  // ===========================================================================
  // Conflict Resolution & Ignore
  // ===========================================================================

  /// Resolves a merge conflict.
  Future<void> resolveConflict(String relativePath, {required bool useOurs}) async {
    final repo = _requireRepo();
    await _runAction('Resolving conflict in $relativePath', () async {
      await _git.resolveConflict(repo, relativePath: relativePath, useOurs: useOurs);
      _events.add(GitOperationEvent.info('Resolved conflict in $relativePath'));
      await _refreshStatusOnly();
    });
  }

  /// Aborts an in-progress merge.
  Future<void> abortMerge() async {
    final repo = _requireRepo();
    await _runAction('Aborting merge', () async {
      await _git.abortMerge(repo);
      _events.add(GitOperationEvent.info('Aborted merge'));
      await _refreshStatusOnly();
    });
  }

  /// Adds a file path or pattern to `.gitignore`.
  Future<void> addToGitignore(String path) async {
    final repo = _requireRepo();
    await _runAction('Adding $path to .gitignore', () async {
      await _git.addToGitignore(repo, path);
      _events.add(GitOperationEvent.info('Added $path to .gitignore'));
      await _refreshStatusOnly();
    });
  }

  // ===========================================================================
  // Diff Inspection (Data layer for future Diff views)
  // ===========================================================================

  /// Retrieves file diff data (unified patch and hunks) for [file].
  Future<GitFileDiff> getFileDiff(GitFileStatus file) async {
    final repo = _requireRepo();
    return _git.getFileDiff(
      repo,
      relativePath: file.path,
      staged: file.isStaged,
    );
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  String _requireRepo() {
    final r = _repoRootPath;
    if (r == null || !_isRepo) {
      throw StateError('No active Git repository in current workspace.');
    }
    return r;
  }

  Future<void> _runAction(String message, Future<void> Function() action) async {
    if (_isBusy) return;
    _isBusy = true;
    _busyMessage = message;
    _lastError = null;
    notifyListeners();

    try {
      await action();
    } catch (e) {
      _lastError = e.toString();
      _events.add(GitOperationEvent.error(message, e.toString()));
      rethrow;
    } finally {
      _isBusy = false;
      _busyMessage = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopWatcher();
    commitMessageController.dispose();
    super.dispose();
  }
}

