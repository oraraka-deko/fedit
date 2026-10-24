import 'dart:io';
import 'dart:isolate';

import 'package:fedit/models/git_models.dart';
import 'package:fedit/services/git_service.dart';
import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Workspace service supporting the demo console and high-level operations,
/// powered by background isolates to eliminate UI freezing.
class GitWorkspaceService {
  GitWorkspaceService({Directory? baseDirectory, GitService? gitService})
      : _baseDirectoryOverride = baseDirectory,
        gitService = gitService ?? const GitService();

  final Directory? _baseDirectoryOverride;
  final GitService gitService;

  Future<Directory> _baseDirectory() async {
    if (_baseDirectoryOverride != null) {
      return _baseDirectoryOverride;
    }

    try {
      return await getApplicationSupportDirectory();
    } on Object {
      return Directory.systemTemp.createTempSync('git2dart-demo-support');
    }
  }

  Future<Directory> workspaceRoot() async {
    final base = await _baseDirectory();
    return Directory(p.join(base.path, 'git2dart_demo_workspace'));
  }

  Future<Directory> repositoryDirectory() async {
    final root = await workspaceRoot();
    return Directory(p.join(root.path, 'workdir'));
  }

  Future<Directory> bareRemoteDirectory() async {
    final root = await workspaceRoot();
    return Directory(p.join(root.path, 'local_remote.git'));
  }

  Future<GitScenarioResult<GitWorkspaceSnapshot>> resetAndSeed() async {
    final root = await workspaceRoot();
    final repoDir = await repositoryDirectory();
    final remoteDir = await bareRemoteDirectory();

    return Isolate.run(() {
      final events = <GitOperationEvent>[];
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
        events.add(GitOperationEvent.info('Removed previous demo workspace'));
      }
      root.createSync(recursive: true);
      repoDir.createSync(recursive: true);

      Repository? repo;
      Repository? bareRepo;
      try {
        repo = Repository.init(path: repoDir.path, initialHead: 'main');
        final config = repo.config;
        config['user.name'] = 'Git2Dart Demo';
        config['user.email'] = 'demo@git2dart.local';
        events.add(GitOperationEvent.info('Initialized repository', repo.path));

        _writeWorkdirFile(repo, 'README.md', '# git2dart demo\n\nSeeded repo.\n');
        _writeWorkdirFile(repo, 'lib/demo.txt', 'hello from git2dart\n');
        final rootOid = _commitAllStatic(
          repo,
          message: 'Seed demo repository\n',
          parents: const [],
        );
        events.add(
          GitOperationEvent.info(
            'Created root commit',
            rootOid.sha.substring(0, 7),
          ),
        );

        final rootCommit = Commit.lookup(repo: repo, oid: rootOid);
        final feature = Branch.create(
          repo: repo,
          name: 'feature/offline-scenarios',
          target: rootCommit,
        );
        feature.free();
        rootCommit.free();

        _checkoutBranchStatic(repo, 'feature/offline-scenarios');
        _writeWorkdirFile(
          repo,
          'feature.txt',
          'A feature branch created through git2dart.\n',
        );
        final featureParent = Commit.lookup(repo: repo, oid: rootOid);
        final featureOid = _commitAllStatic(
          repo,
          message: 'Add feature branch sample\n',
          parents: [featureParent],
        );
        featureParent.free();
        events.add(
          GitOperationEvent.info(
            'Created feature branch commit',
            featureOid.sha.substring(0, 7),
          ),
        );
        _checkoutBranchStatic(repo, 'main');

        bareRepo = Repository.init(
          path: remoteDir.path,
          bare: true,
          initialHead: 'main',
        );
        events.add(GitOperationEvent.info('Initialized local bare remote'));

        final remote = Remote.create(
          repo: repo,
          name: 'local',
          url: remoteDir.path,
        );
        remote.push(refspecs: const ['refs/heads/main:refs/heads/main']);
        remote.free();
        events.add(GitOperationEvent.info('Pushed main to local bare remote'));
      } finally {
        bareRepo?.free();
        repo?.free();
      }

      final snapshot = _snapshotStatic(root.path, repoDir.path, remoteDir.path);
      return GitScenarioResult(value: snapshot, events: events);
    });
  }

  Future<GitScenarioResult<GitWorkspaceSnapshot>> makeWorkingChanges() async {
    final root = await workspaceRoot();
    final repoDir = await repositoryDirectory();
    final remoteDir = await bareRemoteDirectory();

    return Isolate.run(() {
      final events = <GitOperationEvent>[];
      final repo = Repository.open(repoDir.path);
      try {
        _writeWorkdirFile(
          repo,
          'notes/today.txt',
          'Generated at ${DateTime.now().toIso8601String()}\n',
        );
        _appendWorkdirFile(
          repo,
          'README.md',
          '\nWorking tree edit at ${DateTime.now().toIso8601String()}.\n',
        );
        events.add(GitOperationEvent.info('Created unstaged working changes'));
      } finally {
        repo.free();
      }

      final snapshot = _snapshotStatic(root.path, repoDir.path, remoteDir.path);
      return GitScenarioResult(value: snapshot, events: events);
    });
  }

  Future<GitScenarioResult<GitWorkspaceSnapshot>> stageAndCommit() async {
    final root = await workspaceRoot();
    final repoDir = await repositoryDirectory();
    final remoteDir = await bareRemoteDirectory();

    return Isolate.run(() {
      final events = <GitOperationEvent>[];
      final repo = Repository.open(repoDir.path);
      try {
        if (repo.status.isEmpty) {
          _appendWorkdirFile(repo, 'README.md', '\nNo-op demo edit.\n');
        }
        final parent = Commit.lookup(repo: repo, oid: repo.head.target);
        final oid = _commitAllStatic(
          repo,
          message: 'Commit demo working changes\n',
          parents: [parent],
        );
        parent.free();
        events.add(
          GitOperationEvent.info(
            'Staged all changes and committed',
            oid.sha.substring(0, 7),
          ),
        );
      } finally {
        repo.free();
      }

      final snapshot = _snapshotStatic(root.path, repoDir.path, remoteDir.path);
      return GitScenarioResult(value: snapshot, events: events);
    });
  }

  Future<GitScenarioResult<GitWorkspaceSnapshot>> createBranchAndMerge() async {
    final root = await workspaceRoot();
    final repoDir = await repositoryDirectory();
    final remoteDir = await bareRemoteDirectory();

    return Isolate.run(() {
      final events = <GitOperationEvent>[];
      final repo = Repository.open(repoDir.path);
      try {
        final branchName = 'demo/merge-${DateTime.now().millisecondsSinceEpoch}';
        final current = Commit.lookup(repo: repo, oid: repo.head.target);
        final branch = Branch.create(
          repo: repo,
          name: branchName,
          target: current,
        );
        branch.free();
        current.free();

        _checkoutBranchStatic(repo, branchName);
        _writeWorkdirFile(repo, 'merge-demo.txt', 'Merged by git2dart.\n');
        final parent = Commit.lookup(repo: repo, oid: repo.head.target);
        final branchTip = _commitAllStatic(
          repo,
          message: 'Add merge demo file\n',
          parents: [parent],
        );
        parent.free();
        events.add(GitOperationEvent.info('Committed on $branchName'));

        _checkoutBranchStatic(repo, 'main');
        final annotatedBranchTip = AnnotatedCommit.lookup(
          repo: repo,
          oid: branchTip,
        );
        Merge.commit(repo: repo, commit: annotatedBranchTip);
        annotatedBranchTip.free();
        final mergeParent = Commit.lookup(repo: repo, oid: repo.head.target);
        final theirParent = Commit.lookup(repo: repo, oid: branchTip);
        final mergeOid = _commitAllStatic(
          repo,
          message: 'Merge $branchName\n',
          parents: [mergeParent, theirParent],
        );
        repo.stateCleanup();
        mergeParent.free();
        theirParent.free();
        events.add(
          GitOperationEvent.info(
            'Merged branch into main',
            mergeOid.sha.substring(0, 7),
          ),
        );
      } finally {
        repo.free();
      }

      final snapshot = _snapshotStatic(root.path, repoDir.path, remoteDir.path);
      return GitScenarioResult(value: snapshot, events: events);
    });
  }

  Future<GitScenarioResult<GitWorkspaceSnapshot>> stashChanges() async {
    final root = await workspaceRoot();
    final repoDir = await repositoryDirectory();
    final remoteDir = await bareRemoteDirectory();

    return Isolate.run(() {
      final events = <GitOperationEvent>[];
      final repo = Repository.open(repoDir.path);
      try {
        _appendWorkdirFile(repo, 'README.md', '\nStash demo change.\n');
        final signature = Signature.defaultSignature(repo);
        final oid = Stash.create(
          repo: repo,
          stasher: signature,
          message: 'stash demo change',
        );
        signature.free();
        events.add(
          GitOperationEvent.info(
            'Saved working changes to stash',
            oid.sha.substring(0, 7),
          ),
        );
      } finally {
        repo.free();
      }

      final snapshot = _snapshotStatic(root.path, repoDir.path, remoteDir.path);
      return GitScenarioResult(value: snapshot, events: events);
    });
  }

  Future<GitScenarioResult<GitWorkspaceSnapshot>> hardReset() async {
    final root = await workspaceRoot();
    final repoDir = await repositoryDirectory();
    final remoteDir = await bareRemoteDirectory();

    return Isolate.run(() {
      final events = <GitOperationEvent>[];
      final repo = Repository.open(repoDir.path);
      try {
        repo.reset(oid: repo.head.target, resetType: GitReset.hard);
        events.add(GitOperationEvent.info('Hard reset working tree to HEAD'));
      } finally {
        repo.free();
      }

      final snapshot = _snapshotStatic(root.path, repoDir.path, remoteDir.path);
      return GitScenarioResult(value: snapshot, events: events);
    });
  }

  Future<GitScenarioResult<ObjectInspection>> inspectObjects() async {
    final repoDir = await repositoryDirectory();

    return Isolate.run(() {
      final events = <GitOperationEvent>[];
      final repo = Repository.open(repoDir.path);
      try {
        final readmePath = p.join(repo.workdir, 'README.md');
        final fileHash = repo.hashFile(path: readmePath);
        final blobOid = Blob.create(
          repo: repo,
          content: 'blob created from the Objects tab\n',
        );
        final blob = Blob.lookup(repo: repo, oid: blobOid);
        final commit = Commit.lookup(repo: repo, oid: repo.head.target);
        final diff = Diff.indexToWorkdir(repo: repo, index: repo.index);

        final result = ObjectInspection(
          fileHash: fileHash.sha,
          blobSha: blob.oid.sha,
          blobContent: blob.content,
          headTreeSha: commit.treeOid.sha,
          diffPatch: diff.patch,
        );

        diff.free();
        commit.free();
        blob.free();
        events.add(GitOperationEvent.info('Inspected blob, file hash, and diff'));
        return GitScenarioResult(value: result, events: events);
      } finally {
        repo.free();
      }
    });
  }

  Future<GitScenarioResult<GitWorkspaceSnapshot>> pushAndFetchLocalRemote() async {
    final root = await workspaceRoot();
    final repoDir = await repositoryDirectory();
    final remoteDir = await bareRemoteDirectory();

    return Isolate.run(() {
      final events = <GitOperationEvent>[];
      final repo = Repository.open(repoDir.path);
      try {
        Remote remote;
        if (repo.remotes.contains('local')) {
          remote = Remote.lookup(repo: repo, name: 'local');
        } else {
          remote = Remote.create(
            repo: repo,
            name: 'local',
            url: remoteDir.path,
          );
        }

        final callbacks = const AuthSpec.none().toCallbacks(
          transferProgress: (progress) {
            events.add(
              GitOperationEvent.progress(
                'Transfer progress',
                '${progress.receivedObjects}/${progress.totalObjects} objects',
              ),
            );
          },
          updateTips: (refname, oldOid, newOid) {
            events.add(
              GitOperationEvent.progress(
                'Updated $refname',
                '${oldOid.sha.substring(0, 7)} -> ${newOid.sha.substring(0, 7)}',
              ),
            );
          },
          pushUpdateReference: (refname, message) {
            events.add(
              GitOperationEvent.progress(
                'Pushed $refname',
                message.isEmpty ? 'ok' : message,
              ),
            );
          },
        );
        remote.push(
          refspecs: const ['refs/heads/main:refs/heads/main'],
          callbacks: callbacks,
        );
        remote.fetch(
          refspecs: const ['+refs/heads/*:refs/remotes/local/*'],
          callbacks: callbacks,
        );
        remote.free();
        events.add(GitOperationEvent.info('Pushed and fetched local bare remote'));
      } finally {
        repo.free();
      }

      final snapshot = _snapshotStatic(root.path, repoDir.path, remoteDir.path);
      return GitScenarioResult(value: snapshot, events: events);
    });
  }

  Future<GitScenarioResult<RemoteRefsResult>> listRemoteRefs({
    required String url,
    required AuthSpec authSpec,
  }) async {
    final root = await workspaceRoot();
    return Isolate.run(() {
      final events = <GitOperationEvent>[
        GitOperationEvent.info('Using auth session', authSpec.toDisplayString()),
      ];
      final tmp = Directory(
        p.join(
          root.path,
          'remote_probe_${DateTime.now().millisecondsSinceEpoch}',
        ),
      )..createSync(recursive: true);

      Repository? repo;
      Remote? remote;
      try {
        repo = Repository.init(path: tmp.path, initialHead: 'main');
        remote = Remote.create(repo: repo, name: 'probe', url: url);
        final refs = remote.ls(
          callbacks: authSpec.toCallbacks(
            transferProgress: (progress) {
              events.add(
                GitOperationEvent.progress(
                  'Remote transfer',
                  '${progress.receivedObjects}/${progress.totalObjects} objects',
                ),
              );
            },
          ),
        );
        events.add(GitOperationEvent.info('Listed ${refs.length} remote refs'));
        return GitScenarioResult(
          value: RemoteRefsResult(
            refs: refs
                .take(30)
                .map(
                  (ref) => RemoteRefSummary(
                    name: ref.name,
                    oid: ref.oid.sha,
                    symRef: ref.symRef,
                  ),
                )
                .toList(),
          ),
          events: events,
        );
      } finally {
        remote?.free();
        repo?.free();
        if (tmp.existsSync()) {
          tmp.deleteSync(recursive: true);
        }
      }
    });
  }

  Future<GitWorkspaceSnapshot> snapshot() async {
    final root = await workspaceRoot();
    final repoDir = await repositoryDirectory();
    final remoteDir = await bareRemoteDirectory();

    return Isolate.run(() {
      return _snapshotStatic(root.path, repoDir.path, remoteDir.path);
    });
  }

  Future<PlatformDiagnostics> diagnostics() async {
    final root = await workspaceRoot();
    return gitService.getDiagnostics(root.path);
  }

  // ===========================================================================
  // Static Isolate Helpers
  // ===========================================================================

  static GitWorkspaceSnapshot _snapshotStatic(
    String workspacePath,
    String repoPath,
    String bareRemotePath,
  ) {
    final repoDir = Directory(repoPath);
    if (!Directory(p.join(repoDir.path, '.git')).existsSync()) {
      return GitWorkspaceSnapshot.empty;
    }

    final repo = Repository.open(repoDir.path);
    try {
      final head = repo.head;
      final status = repo.status;
      final branches = repo.branches;
      final allCommits = repo.log(oid: head.target);
      final visibleCommits = allCommits.take(12).toList();

      final snapshot = GitWorkspaceSnapshot(
        workspacePath: workspacePath,
        repoPath: repoPath,
        bareRemotePath: bareRemotePath,
        headName: head.shorthand,
        headSha: head.target.sha,
        isClean: status.isEmpty,
        branches: branches.map((branch) => branch.name).toList()..sort(),
        remotes: repo.remotes,
        statusEntries: status.entries
            .map(
              (entry) => StatusEntry(
                path: entry.key,
                statuses: entry.value.map((status) => status.name).toList()..sort(),
              ),
            )
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path)),
        commits: visibleCommits.map(_commitSummaryStatic).toList(),
        files: _trackedVisibleFilesStatic(repoDir),
      );

      for (final commit in allCommits) {
        commit.free();
      }
      for (final branch in branches) {
        branch.free();
      }
      head.free();

      return snapshot;
    } finally {
      repo.free();
    }
  }

  static Oid _commitAllStatic(
    Repository repo, {
    required String message,
    required List<Commit> parents,
  }) {
    final index = repo.index;
    index.addAll(const ['*']);
    index.write();
    final tree = Tree.lookup(repo: repo, oid: index.writeTree());
    final signature = Signature.defaultSignature(repo);
    try {
      return Commit.create(
        repo: repo,
        updateRef: 'HEAD',
        author: signature,
        committer: signature,
        message: message,
        tree: tree,
        parents: parents,
      );
    } finally {
      signature.free();
      tree.free();
      index.free();
    }
  }

  static void _checkoutBranchStatic(Repository repo, String branchName) {
    final refName = 'refs/heads/$branchName';
    Checkout.reference(repo: repo, name: refName);
    repo.setHead(refName);
  }

  static void _writeWorkdirFile(Repository repo, String relativePath, String content) {
    final file = File(p.join(repo.workdir, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  static void _appendWorkdirFile(
    Repository repo,
    String relativePath,
    String content,
  ) {
    final file = File(p.join(repo.workdir, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content, mode: FileMode.append);
  }

  static CommitSummary _commitSummaryStatic(Commit commit) {
    final author = commit.author;
    try {
      return CommitSummary(
        sha: commit.oid.sha,
        summary: commit.summary,
        author: author.name,
        email: author.email,
        time: DateTime.fromMillisecondsSinceEpoch(commit.time * 1000),
        parentCount: commit.parents.length,
      );
    } finally {
      author.free();
    }
  }

  static List<String> _trackedVisibleFilesStatic(Directory repoDir) {
    if (!repoDir.existsSync()) {
      return const [];
    }

    final files = <String>[];
    for (final entity in repoDir.listSync(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final relative = p.relative(entity.path, from: repoDir.path);
      if (relative == '.git' || relative.startsWith('.git${p.separator}')) {
        continue;
      }
      files.add(relative.replaceAll(r'\', '/'));
    }
    files.sort();
    return files;
  }
}
