import 'package:git2dart/git2dart.dart';

/// Authentication modes supported for remote Git operations.
enum AuthMode { none, httpsUserPass, sshKeyFiles, sshKeyMemory, sshAgent }

/// Specifications and credentials for Git remote operations (fetch, pull, push, ls).
class AuthSpec {
  const AuthSpec({
    required this.mode,
    this.username = '',
    this.password = '',
    this.publicKeyPath = '',
    this.privateKeyPath = '',
    this.publicKey = '',
    this.privateKey = '',
    this.passphrase = '',
  });

  const AuthSpec.none() : this(mode: AuthMode.none);

  final AuthMode mode;
  final String username;
  final String password;
  final String publicKeyPath;
  final String privateKeyPath;
  final String publicKey;
  final String privateKey;
  final String passphrase;

  bool get isReady {
    return switch (mode) {
      AuthMode.none => true,
      AuthMode.httpsUserPass => username.isNotEmpty && password.isNotEmpty,
      AuthMode.sshKeyFiles =>
        username.isNotEmpty &&
            publicKeyPath.isNotEmpty &&
            privateKeyPath.isNotEmpty,
      AuthMode.sshKeyMemory =>
        username.isNotEmpty && publicKey.isNotEmpty && privateKey.isNotEmpty,
      AuthMode.sshAgent => username.isNotEmpty,
    };
  }

  Callbacks toCallbacks({
    void Function(TransferProgress progress)? transferProgress,
    void Function(String message, int length, void payload)? sidebandProgress,
    void Function(String refname, Oid oldOid, Oid newOid)? updateTips,
    void Function(String refname, String message)? pushUpdateReference,
  }) {
    return Callbacks(
      credentials: _credentials(),
      transferProgress: transferProgress,
      sidebandProgress: sidebandProgress,
      updateTips: updateTips,
      pushUpdateReference: pushUpdateReference,
    );
  }

  Credentials? _credentials() {
    return switch (mode) {
      AuthMode.none => null,
      AuthMode.httpsUserPass => UserPass(
        username: username,
        password: password,
      ),
      AuthMode.sshKeyFiles => Keypair(
        username: username,
        pubKey: publicKeyPath,
        privateKey: privateKeyPath,
        passPhrase: passphrase,
      ),
      AuthMode.sshKeyMemory => KeypairFromMemory(
        username: username,
        pubKey: publicKey,
        privateKey: privateKey,
        passPhrase: passphrase,
      ),
      AuthMode.sshAgent => KeypairFromAgent(username),
    };
  }

  String toDisplayString() {
    return switch (mode) {
      AuthMode.none => 'No credentials',
      AuthMode.httpsUserPass =>
        'HTTPS user/password: user=$username, password=${_redacted(password)}',
      AuthMode.sshKeyFiles =>
        'SSH key files: user=$username, public=$publicKeyPath, private=${_basename(privateKeyPath)}, passphrase=${_redacted(passphrase)}',
      AuthMode.sshKeyMemory =>
        'SSH key memory: user=$username, public=${_redacted(publicKey)}, private=${_redacted(privateKey)}, passphrase=${_redacted(passphrase)}',
      AuthMode.sshAgent => 'SSH agent: user=$username',
    };
  }

  static String _redacted(String value) => value.isEmpty ? '<empty>' : '<set>';

  static String _basename(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final index = normalized.lastIndexOf('/');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }
}

/// Author signature for commits and stashes.
class GitAuthor {
  const GitAuthor({required this.name, required this.email});

  final String name;
  final String email;

  static const defaultAuthor = GitAuthor(
    name: 'Git User',
    email: 'user@workspace.local',
  );
}

/// The grouping of a changed file corresponding to VS Code Source Control panels.
enum GitFileStatusGroup {
  /// Staged changes ready to be committed (`git add`).
  staged,

  /// Working tree changes (tracked files modified or deleted in workdir).
  workingTree,

  /// Untracked files (new files not yet added to index).
  untracked,

  /// Merge conflicts requiring manual or tool resolution.
  mergeConflict,
}

/// Delta status of a file within a Git repository.
enum GitFileDeltaStatus {
  modified,
  added,
  deleted,
  renamed,
  copied,
  untracked,
  ignored,
  unmerged,
  typeChange;

  /// Single-letter status code matching git status / VS Code badges.
  String get letterBadge {
    return switch (this) {
      GitFileDeltaStatus.modified => 'M',
      GitFileDeltaStatus.added => 'A',
      GitFileDeltaStatus.deleted => 'D',
      GitFileDeltaStatus.renamed => 'R',
      GitFileDeltaStatus.copied => 'C',
      GitFileDeltaStatus.untracked => 'U',
      GitFileDeltaStatus.ignored => '!',
      GitFileDeltaStatus.unmerged => '!',
      GitFileDeltaStatus.typeChange => 'T',
    };
  }

  String get label {
    return switch (this) {
      GitFileDeltaStatus.modified => 'Modified',
      GitFileDeltaStatus.added => 'Added',
      GitFileDeltaStatus.deleted => 'Deleted',
      GitFileDeltaStatus.renamed => 'Renamed',
      GitFileDeltaStatus.copied => 'Copied',
      GitFileDeltaStatus.untracked => 'Untracked',
      GitFileDeltaStatus.ignored => 'Ignored',
      GitFileDeltaStatus.unmerged => 'Conflict',
      GitFileDeltaStatus.typeChange => 'Type Changed',
    };
  }
}

/// A changed file in the repository formatted for Source Control views.
class GitFileStatus {
  const GitFileStatus({
    required this.path,
    required this.group,
    required this.status,
    this.oldPath,
    this.stagedFlags = const [],
    this.workingCopyFlags = const [],
  });

  /// Path of the file relative to repository root (always forward slashes).
  final String path;

  /// Old relative path if renamed or copied.
  final String? oldPath;

  /// VS Code Source Control section group.
  final GitFileStatusGroup group;

  /// File change status.
  final GitFileDeltaStatus status;

  /// Raw git2dart GitStatus names present in the index.
  final List<String> stagedFlags;

  /// Raw git2dart GitStatus names present in the working copy.
  final List<String> workingCopyFlags;

  bool get isStaged => group == GitFileStatusGroup.staged;
  bool get isUntracked => group == GitFileStatusGroup.untracked;
  bool get isConflicted => group == GitFileStatusGroup.mergeConflict;
  bool get isModified => status == GitFileDeltaStatus.modified;
  bool get isDeleted => status == GitFileDeltaStatus.deleted;
  bool get isAdded => status == GitFileDeltaStatus.added;
  bool get isRenamed => status == GitFileDeltaStatus.renamed;

  /// File name without parent directories.
  String get fileName {
    final idx = path.lastIndexOf('/');
    return idx == -1 ? path : path.substring(idx + 1);
  }

  /// Parent directory relative path (e.g. `lib/models`).
  String get directoryPath {
    final idx = path.lastIndexOf('/');
    return idx == -1 ? '' : path.substring(0, idx);
  }
}

/// Full status snapshot of a workspace repository matching VS Code Source Control.
class GitWorkspaceStatus {
  const GitWorkspaceStatus({
    required this.repoPath,
    required this.workdirPath,
    required this.currentBranch,
    required this.headSha,
    required this.headMessage,
    required this.isDetached,
    required this.isEmpty,
    required this.upstreamBranch,
    required this.aheadCount,
    required this.behindCount,
    required this.isMerging,
    required this.isRebasing,
    required this.stagedChanges,
    required this.workingTreeChanges,
    required this.untrackedChanges,
    required this.mergeConflicts,
  });

  final String repoPath;
  final String workdirPath;
  final String? currentBranch;
  final String? headSha;
  final String? headMessage;
  final bool isDetached;
  final bool isEmpty;
  final String? upstreamBranch;
  final int aheadCount;
  final int behindCount;
  final bool isMerging;
  final bool isRebasing;
  final List<GitFileStatus> stagedChanges;
  final List<GitFileStatus> workingTreeChanges;
  final List<GitFileStatus> untrackedChanges;
  final List<GitFileStatus> mergeConflicts;

  bool get isClean =>
      stagedChanges.isEmpty &&
      workingTreeChanges.isEmpty &&
      untrackedChanges.isEmpty &&
      mergeConflicts.isEmpty;

  int get totalChangesCount =>
      stagedChanges.length +
      workingTreeChanges.length +
      untrackedChanges.length +
      mergeConflicts.length;

  static const empty = GitWorkspaceStatus(
    repoPath: '',
    workdirPath: '',
    currentBranch: null,
    headSha: null,
    headMessage: null,
    isDetached: false,
    isEmpty: true,
    upstreamBranch: null,
    aheadCount: 0,
    behindCount: 0,
    isMerging: false,
    isRebasing: false,
    stagedChanges: [],
    workingTreeChanges: [],
    untrackedChanges: [],
    mergeConflicts: [],
  );
}

/// Information about a Git branch (local or remote).
class GitBranchData {
  const GitBranchData({
    required this.name,
    required this.shorthand,
    required this.isCurrent,
    required this.isRemote,
    required this.targetSha,
    this.upstreamName,
    this.ahead = 0,
    this.behind = 0,
  });

  /// Full reference name, e.g. `refs/heads/main` or `refs/remotes/origin/main`.
  final String name;

  /// Human-friendly shorthand, e.g. `main` or `origin/main`.
  final String shorthand;

  /// Whether this branch is currently checked out.
  final bool isCurrent;

  /// Whether this is a remote tracking branch.
  final bool isRemote;

  /// SHA of the commit this branch points to.
  final String targetSha;

  /// Upstream branch shorthand if configured.
  final String? upstreamName;

  /// Number of commits ahead of upstream.
  final int ahead;

  /// Number of commits behind upstream.
  final int behind;
}

typedef GitBranchInfo = GitBranchData;

/// Remote repository configuration.
class GitRemote {
  const GitRemote({
    required this.name,
    required this.fetchUrl,
    required this.pushUrl,
  });

  final String name;
  final String fetchUrl;
  final String pushUrl;
}

/// Summary of a commit in the repository log.
class GitCommitSummary {
  const GitCommitSummary({
    required this.sha,
    required this.shortSha,
    required this.summary,
    required this.authorName,
    required this.authorEmail,
    required this.time,
    required this.parentCount,
    required this.parentShas,
  });

  final String sha;
  final String shortSha;
  final String summary;
  final String authorName;
  final String authorEmail;
  final DateTime time;
  final int parentCount;
  final List<String> parentShas;
}

/// Detailed commit info including message and stats.
class GitCommitDetail {
  const GitCommitDetail({
    required this.sha,
    required this.summary,
    required this.message,
    required this.authorName,
    required this.authorEmail,
    required this.committerName,
    required this.committerEmail,
    required this.time,
    required this.parentShas,
    required this.filesChanged,
    required this.insertions,
    required this.deletions,
  });

  final String sha;
  final String summary;
  final String message;
  final String authorName;
  final String authorEmail;
  final String committerName;
  final String committerEmail;
  final DateTime time;
  final List<String> parentShas;
  final int filesChanged;
  final int insertions;
  final int deletions;
}

/// Stashed work entry.
class GitStashData {
  const GitStashData({
    required this.index,
    required this.message,
    required this.sha,
  });

  final int index;
  final String message;
  final String sha;
}

typedef GitStashInfo = GitStashData;

/// Git tag metadata.
class GitTagData {
  const GitTagData({
    required this.name,
    required this.targetSha,
    this.message,
    this.taggerName,
    this.taggerEmail,
    this.time,
  });

  final String name;
  final String targetSha;
  final String? message;
  final String? taggerName;
  final String? taggerEmail;
  final DateTime? time;
}

typedef GitTagInfo = GitTagData;

/// Single line in a diff hunk.
enum GitDiffLineType { context, addition, deletion }

class GitDiffLineData {
  const GitDiffLineData({
    required this.type,
    required this.content,
    this.oldLineNumber,
    this.newLineNumber,
  });

  final GitDiffLineType type;
  final String content;
  final int? oldLineNumber;
  final int? newLineNumber;
}

typedef GitDiffLineInfo = GitDiffLineData;

/// A hunk within a file diff.
class GitDiffHunk {
  const GitDiffHunk({
    required this.oldStart,
    required this.oldLines,
    required this.newStart,
    required this.newLines,
    required this.header,
    required this.lines,
  });

  final int oldStart;
  final int oldLines;
  final int newStart;
  final int newLines;
  final String header;
  final List<GitDiffLineData> lines;
}

/// Diff details for a single file.
class GitFileDiff {
  const GitFileDiff({
    required this.oldPath,
    required this.newPath,
    required this.isNew,
    required this.isDeleted,
    required this.isRenamed,
    required this.patchText,
    required this.additions,
    required this.deletions,
    required this.hunks,
  });

  final String oldPath;
  final String newPath;
  final bool isNew;
  final bool isDeleted;
  final bool isRenamed;
  final String patchText;
  final int additions;
  final int deletions;
  final List<GitDiffHunk> hunks;

  static const empty = GitFileDiff(
    oldPath: '',
    newPath: '',
    isNew: false,
    isDeleted: false,
    isRenamed: false,
    patchText: '',
    additions: 0,
    deletions: 0,
    hunks: [],
  );
}

/// Events emitted during Git operations.
class GitOperationEvent {
  const GitOperationEvent({
    required this.kind,
    required this.message,
    required this.timestamp,
    this.details = '',
  });

  factory GitOperationEvent.info(String message, [String details = '']) {
    return GitOperationEvent(
      kind: GitOperationEventKind.info,
      message: message,
      timestamp: DateTime.now(),
      details: details,
    );
  }

  factory GitOperationEvent.progress(String message, [String details = '']) {
    return GitOperationEvent(
      kind: GitOperationEventKind.progress,
      message: message,
      timestamp: DateTime.now(),
      details: details,
    );
  }

  factory GitOperationEvent.error(String message, [String details = '']) {
    return GitOperationEvent(
      kind: GitOperationEventKind.error,
      message: message,
      timestamp: DateTime.now(),
      details: details,
    );
  }

  final GitOperationEventKind kind;
  final String message;
  final String details;
  final DateTime timestamp;
}

enum GitOperationEventKind { info, progress, error }

class GitScenarioResult<T> {
  const GitScenarioResult({required this.value, required this.events});

  final T value;
  final List<GitOperationEvent> events;
}

/// Backwards compatibility models for demo console
class CommitSummary {
  const CommitSummary({
    required this.sha,
    required this.summary,
    required this.author,
    required this.email,
    required this.time,
    required this.parentCount,
  });

  final String sha;
  final String summary;
  final String author;
  final String email;
  final DateTime time;
  final int parentCount;
}

class StatusEntry {
  const StatusEntry({required this.path, required this.statuses});

  final String path;
  final List<String> statuses;
}

class GitWorkspaceSnapshot {
  const GitWorkspaceSnapshot({
    required this.workspacePath,
    required this.repoPath,
    required this.bareRemotePath,
    required this.headName,
    required this.headSha,
    required this.isClean,
    required this.branches,
    required this.remotes,
    required this.statusEntries,
    required this.commits,
    required this.files,
  });

  final String workspacePath;
  final String repoPath;
  final String bareRemotePath;
  final String headName;
  final String headSha;
  final bool isClean;
  final List<String> branches;
  final List<String> remotes;
  final List<StatusEntry> statusEntries;
  final List<CommitSummary> commits;
  final List<String> files;

  static const empty = GitWorkspaceSnapshot(
    workspacePath: '',
    repoPath: '',
    bareRemotePath: '',
    headName: '',
    headSha: '',
    isClean: true,
    branches: [],
    remotes: [],
    statusEntries: [],
    commits: [],
    files: [],
  );
}

class ObjectInspection {
  const ObjectInspection({
    required this.fileHash,
    required this.blobSha,
    required this.blobContent,
    required this.headTreeSha,
    required this.diffPatch,
  });

  final String fileHash;
  final String blobSha;
  final String blobContent;
  final String headTreeSha;
  final String diffPatch;
}

class RemoteRefsResult {
  const RemoteRefsResult({required this.refs});

  final List<RemoteRefSummary> refs;
}

class RemoteRefSummary {
  const RemoteRefSummary({
    required this.name,
    required this.oid,
    required this.symRef,
  });

  final String name;
  final String oid;
  final String symRef;
}

class PlatformDiagnostics {
  const PlatformDiagnostics({
    required this.platformLabel,
    required this.libgit2Version,
    required this.storagePath,
    required this.platformReady,
    required this.notes,
  });

  final String platformLabel;
  final String libgit2Version;
  final String storagePath;
  final bool platformReady;
  final List<String> notes;
}
