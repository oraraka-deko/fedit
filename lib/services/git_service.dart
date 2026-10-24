import 'dart:io';
import 'dart:isolate';
import 'package:fedit/models/git_models.dart';
import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;

/// Standalone, robust Git service.
///
/// All operations execute in background isolates via [Isolate.run] to ensure
/// zero UI thread blocking or freezing. All native libgit2 resources are
/// safely allocated, cleaned, and freed inside the isolate, returning pure,
/// immutable Dart model objects.
class GitService {
  const GitService();

  // ===========================================================================
  // Repository Lifecycle & Discovery
  // ===========================================================================

  /// Checks if [path] is inside or points to a valid Git repository.
  Future<bool> isRepository(String path) async {
    return Isolate.run(() {
      try {
        final root = Repository.discover(startPath: path);
        return root.isNotEmpty;
      } catch (_) {
        return false;
      }
    });
  }

  /// Discovers and returns the root `.git` / workdir directory for [startPath].
  Future<String?> findRepositoryRoot(String startPath) async {
    return Isolate.run(() {
      try {
        final discovered = Repository.discover(startPath: startPath);
        if (discovered.isEmpty) return null;
        final normalized = discovered.replaceAll(r'\', '/');
        if (normalized.endsWith('/.git') || normalized.endsWith('/.git/')) {
          final parent = Directory(discovered).parent.path;
          return parent.replaceAll(r'\', '/');
        }
        return normalized;
      } catch (_) {
        return null;
      }
    });
  }

  /// Initializes a new repository at [path].
  Future<void> initRepository({
    required String path,
    bool bare = false,
    String initialHead = 'main',
    GitAuthor? author,
  }) async {
    await Isolate.run(() {
      final repo = Repository.init(
        path: path,
        bare: bare,
        initialHead: initialHead,
      );
      try {
        final config = repo.config;
        final auth = author ?? GitAuthor.defaultAuthor;
        config['user.name'] = auth.name;
        config['user.email'] = auth.email;
      } finally {
        repo.free();
      }
    });
  }

  /// Clones a remote repository at [url] into [localPath].
  Future<void> cloneRepository({
    required String url,
    required String localPath,
    String? branch,
    AuthSpec? authSpec,
    GitAuthor? author,
  }) async {
    final spec = authSpec ?? const AuthSpec.none();
    await Isolate.run(() {
      final callbacks = spec.toCallbacks();
      final repo = Repository.clone(
        url: url,
        localPath: localPath,
        checkoutBranch: branch,
        callbacks: callbacks,
      );
      try {
        final config = repo.config;
        final auth = author ?? GitAuthor.defaultAuthor;
        config['user.name'] = auth.name;
        config['user.email'] = auth.email;
      } finally {
        repo.free();
      }
    });
  }

  // ===========================================================================
  // Workspace Status & VS Code SCM Mapping
  // ===========================================================================

  /// Retrieves the complete status snapshot of [repoPath] mapped to VS Code
  /// Source Control groups (Staged, Working Tree Changes, Untracked, Merge Conflicts).
  Future<GitWorkspaceStatus> getStatus(String repoPath) async {
    return Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final isBare = repo.isBare;
        final isUnborn = repo.isBranchUnborn;
        final workdir = isBare ? repo.path : repo.workdir;

        String? currentBranchName;
        String? headSha;
        String? headMessage;
        bool isDetached = false;
        String? upstreamName;
        int ahead = 0;
        int behind = 0;

        if (!isUnborn) {
          try {
            isDetached = repo.isHeadDetached;
            final headRef = repo.head;
            headSha = headRef.target.sha;
            currentBranchName = headRef.shorthand;

            final headCommit = Commit.lookup(repo: repo, oid: headRef.target);
            headMessage = headCommit.summary;
            headCommit.free();
            headRef.free();

            // Compute upstream tracking & ahead/behind if not detached
            if (!isDetached && currentBranchName.isNotEmpty) {
              for (final b in repo.branches) {
                if (b.name == currentBranchName) {
                  try {
                    final up = b.upstream;
                    upstreamName = up.shorthand;
                    final counts = repo.aheadBehind(
                      local: repo.head.target,
                      upstream: up.target,
                    );
                    ahead = counts[0];
                    behind = counts[1];
                    up.free();
                  } catch (_) {}
                }
                b.free();
              }
            }
          } catch (_) {}
        } else {
          // In unborn state, inspect .git/HEAD file to extract the branch name
          try {
            final headFile = File(p.join(repo.path, 'HEAD'));
            if (headFile.existsSync()) {
              final content = headFile.readAsStringSync().trim();
              if (content.startsWith('ref: refs/heads/')) {
                currentBranchName = content.substring('ref: refs/heads/'.length);
              }
            }
          } catch (_) {}
        }

        final isMerging = repo.state == GitRepositoryState.merge;
        final isRebasing =
            repo.state == GitRepositoryState.rebase ||
            repo.state == GitRepositoryState.rebaseInteractive ||
            repo.state == GitRepositoryState.rebaseMerge;

        final stagedChanges = <GitFileStatus>[];
        final workingTreeChanges = <GitFileStatus>[];
        final untrackedChanges = <GitFileStatus>[];
        final mergeConflicts = <GitFileStatus>[];

        // Gather raw status and scan for untracked files
        final rawStatus = Map<String, Set<GitStatus>>.from(repo.status);

        if (!isBare) {
          final workdirDir = Directory(workdir);
          if (workdirDir.existsSync()) {
            for (final entity in workdirDir.listSync(recursive: true)) {
              if (entity is! File) continue;
              final rel = p.relative(entity.path, from: workdir).replaceAll(r'\', '/');
              if (rel == '.git' || rel.startsWith('.git/')) continue;

              if (!rawStatus.containsKey(rel)) {
                if (!Ignore.pathIsIgnored(repo: repo, path: rel)) {
                  final fileStatuses = repo.statusFile(rel);
                  if (fileStatuses.isNotEmpty && !fileStatuses.contains(GitStatus.current)) {
                    rawStatus[rel] = fileStatuses;
                  }
                }
              }
            }
          }
        }

        for (final entry in rawStatus.entries) {
          final filePath = entry.key.replaceAll(r'\', '/');
          final flags = entry.value;

          final flagNames = flags.map((f) => f.name).toList();
          final isConflicted = flags.contains(GitStatus.conflicted);

          if (isConflicted) {
            mergeConflicts.add(
              GitFileStatus(
                path: filePath,
                group: GitFileStatusGroup.mergeConflict,
                status: GitFileDeltaStatus.unmerged,
                workingCopyFlags: flagNames,
              ),
            );
            continue;
          }

          // 1. Check Staged Changes (index flags)
          final hasIndexNew = flags.contains(GitStatus.indexNew);
          final hasIndexMod = flags.contains(GitStatus.indexModified);
          final hasIndexDel = flags.contains(GitStatus.indexDeleted);
          final hasIndexRen = flags.contains(GitStatus.indexRenamed);
          final hasIndexType = flags.contains(GitStatus.indexTypeChange);

          if (hasIndexNew ||
              hasIndexMod ||
              hasIndexDel ||
              hasIndexRen ||
              hasIndexType) {
            final GitFileDeltaStatus deltaStatus;
            if (hasIndexNew) {
              deltaStatus = GitFileDeltaStatus.added;
            } else if (hasIndexMod) {
              deltaStatus = GitFileDeltaStatus.modified;
            } else if (hasIndexDel) {
              deltaStatus = GitFileDeltaStatus.deleted;
            } else if (hasIndexRen) {
              deltaStatus = GitFileDeltaStatus.renamed;
            } else {
              deltaStatus = GitFileDeltaStatus.typeChange;
            }

            stagedChanges.add(
              GitFileStatus(
                path: filePath,
                group: GitFileStatusGroup.staged,
                status: deltaStatus,
                stagedFlags: flagNames,
              ),
            );
          }

          // 2. Check Untracked files (wtNew without index entry)
          final hasWtNew = flags.contains(GitStatus.wtNew);
          if (hasWtNew && !hasIndexNew) {
            untrackedChanges.add(
              GitFileStatus(
                path: filePath,
                group: GitFileStatusGroup.untracked,
                status: GitFileDeltaStatus.untracked,
                workingCopyFlags: flagNames,
              ),
            );
            continue;
          }

          // 3. Check Working Tree Changes (wtModified, wtDeleted, etc.)
          final hasWtMod = flags.contains(GitStatus.wtModified);
          final hasWtDel = flags.contains(GitStatus.wtDeleted);
          final hasWtRen = flags.contains(GitStatus.wtRenamed);
          final hasWtType = flags.contains(GitStatus.wtTypeChange);

          if (hasWtMod || hasWtDel || hasWtRen || hasWtType) {
            final GitFileDeltaStatus wtDeltaStatus;
            if (hasWtMod) {
              wtDeltaStatus = GitFileDeltaStatus.modified;
            } else if (hasWtDel) {
              wtDeltaStatus = GitFileDeltaStatus.deleted;
            } else if (hasWtRen) {
              wtDeltaStatus = GitFileDeltaStatus.renamed;
            } else {
              wtDeltaStatus = GitFileDeltaStatus.typeChange;
            }

            workingTreeChanges.add(
              GitFileStatus(
                path: filePath,
                group: GitFileStatusGroup.workingTree,
                status: wtDeltaStatus,
                workingCopyFlags: flagNames,
              ),
            );
          }
        }

        stagedChanges.sort((a, b) => a.path.compareTo(b.path));
        workingTreeChanges.sort((a, b) => a.path.compareTo(b.path));
        untrackedChanges.sort((a, b) => a.path.compareTo(b.path));
        mergeConflicts.sort((a, b) => a.path.compareTo(b.path));

        return GitWorkspaceStatus(
          repoPath: repo.path.replaceAll(r'\', '/'),
          workdirPath: workdir.replaceAll(r'\', '/'),
          currentBranch: currentBranchName,
          headSha: headSha,
          headMessage: headMessage,
          isDetached: isDetached,
          isEmpty: isUnborn,
          upstreamBranch: upstreamName,
          aheadCount: ahead,
          behindCount: behind,
          isMerging: isMerging,
          isRebasing: isRebasing,
          stagedChanges: stagedChanges,
          workingTreeChanges: workingTreeChanges,
          untrackedChanges: untrackedChanges,
          mergeConflicts: mergeConflicts,
        );
      } finally {
        repo.free();
      }
    });
  }

  // ===========================================================================
  // Staging & Unstaging (git add, git reset HEAD <file>)
  // ===========================================================================

  /// Stages a single file (`git add <file>` or `git rm <file>` if deleted).
  Future<void> stageFile(String repoPath, String relativePath) async {
    return stageFiles(repoPath, [relativePath]);
  }

  /// Stages multiple files.
  Future<void> stageFiles(String repoPath, List<String> relativePaths) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      final idx = repo.index;
      try {
        final workdir = repo.workdir;
        for (final rel in relativePaths) {
          final normalized = rel.replaceAll(r'\', '/');
          final file = File(p.join(workdir, normalized));
          if (file.existsSync()) {
            idx.add(normalized);
          } else {
            idx.remove(normalized);
          }
        }
        idx.write();
      } finally {
        idx.free();
        repo.free();
      }
    });
  }

  /// Stages all working tree and untracked changes (`git add -A`).
  Future<void> stageAll(String repoPath) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      final idx = repo.index;
      try {
        final workdir = repo.workdir;
        final rawStatus = Map<String, Set<GitStatus>>.from(repo.status);
        final workdirDir = Directory(workdir);

        if (workdirDir.existsSync()) {
          for (final entity in workdirDir.listSync(recursive: true)) {
            if (entity is! File) continue;
            final rel = p.relative(entity.path, from: workdir).replaceAll(r'\', '/');
            if (rel == '.git' || rel.startsWith('.git/')) continue;
            if (!rawStatus.containsKey(rel)) {
              if (!Ignore.pathIsIgnored(repo: repo, path: rel)) {
                rawStatus[rel] = {GitStatus.wtNew};
              }
            }
          }
        }

        for (final entry in rawStatus.entries) {
          final rel = entry.key.replaceAll(r'\', '/');
          final flags = entry.value;
          if (flags.contains(GitStatus.wtDeleted)) {
            idx.remove(rel);
          } else {
            final f = File(p.join(workdir, rel));
            if (f.existsSync()) {
              idx.add(rel);
            } else {
              idx.remove(rel);
            }
          }
        }
        idx.write();
      } finally {
        idx.free();
        repo.free();
      }
    });
  }

  /// Unstages a single file (`git restore --staged <file>` / `git reset HEAD <file>`).
  Future<void> unstageFile(String repoPath, String relativePath) async {
    return unstageFiles(repoPath, [relativePath]);
  }

  /// Unstages multiple files.
  Future<void> unstageFiles(String repoPath, List<String> relativePaths) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      final idx = repo.index;
      try {
        if (!repo.isBranchUnborn) {
          final headRef = repo.head;
          repo.resetDefault(
            oid: headRef.target,
            pathspec: relativePaths.map((p) => p.replaceAll(r'\', '/')).toList(),
          );
          headRef.free();
        } else {
          for (final rel in relativePaths) {
            idx.remove(rel.replaceAll(r'\', '/'));
          }
          idx.write();
        }
      } finally {
        idx.free();
        repo.free();
      }
    });
  }

  /// Unstages all staged files (`git restore --staged .` / `git reset HEAD`).
  Future<void> unstageAll(String repoPath) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      final idx = repo.index;
      try {
        if (!repo.isBranchUnborn) {
          final headRef = repo.head;
          repo.reset(oid: headRef.target, resetType: GitReset.mixed);
          headRef.free();
        } else {
          idx.clear();
          idx.write();
        }
      } finally {
        idx.free();
        repo.free();
      }
    });
  }

  // ===========================================================================
  // Discard Changes (VS Code "Discard Changes")
  // ===========================================================================

  /// Discards changes in a single file.
  Future<void> discardFile(String repoPath, String relativePath) async {
    return discardFiles(repoPath, [relativePath]);
  }

  /// Discards changes in multiple files.
  Future<void> discardFiles(String repoPath, List<String> relativePaths) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final workdir = repo.workdir;
        final statusMap = repo.status;
        final trackedToCheckout = <String>[];

        for (final rel in relativePaths) {
          final normalized = rel.replaceAll(r'\', '/');
          final statuses = statusMap[normalized] ?? const {};

          if (statuses.contains(GitStatus.wtNew) &&
              !statuses.contains(GitStatus.indexNew)) {
            final f = File(p.join(workdir, normalized));
            if (f.existsSync()) {
              f.deleteSync();
            }
          } else {
            trackedToCheckout.add(normalized);
          }
        }

        if (trackedToCheckout.isNotEmpty && !repo.isBranchUnborn) {
          Checkout.head(
            repo: repo,
            paths: trackedToCheckout,
            strategy: const {
              GitCheckout.force,
              GitCheckout.recreateMissing,
            },
          );
        }
      } finally {
        repo.free();
      }
    });
  }

  /// Discards all working tree changes and removes all untracked files.
  Future<void> discardAll(String repoPath) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final workdir = repo.workdir;
        final statusMap = repo.status;
        final untracked = <String>[];

        for (final entry in statusMap.entries) {
          if (entry.value.contains(GitStatus.wtNew) &&
              !entry.value.contains(GitStatus.indexNew)) {
            untracked.add(entry.key.replaceAll(r'\', '/'));
          }
        }

        for (final u in untracked) {
          final f = File(p.join(workdir, u));
          if (f.existsSync()) {
            f.deleteSync();
          }
        }

        if (!repo.isBranchUnborn) {
          Checkout.head(
            repo: repo,
            strategy: const {
              GitCheckout.force,
              GitCheckout.recreateMissing,
            },
          );
        }
      } finally {
        repo.free();
      }
    });
  }

  /// Cleans untracked files from repository working tree (`git clean -f`).
  Future<void> cleanUntracked(String repoPath) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final workdir = repo.workdir;
        final statusMap = repo.status;
        for (final entry in statusMap.entries) {
          if (entry.value.contains(GitStatus.wtNew) &&
              !entry.value.contains(GitStatus.indexNew)) {
            final f = File(p.join(workdir, entry.key));
            if (f.existsSync()) {
              f.deleteSync();
            }
          }
        }
      } finally {
        repo.free();
      }
    });
  }

  // ===========================================================================
  // Commits & Log
  // ===========================================================================

  /// Commits current staged changes.
  Future<String> commit(
    String repoPath, {
    required String message,
    GitAuthor? author,
    bool amend = false,
    bool stageAllBeforeCommit = false,
  }) async {
    return Isolate.run(() {
      final repo = Repository.open(repoPath);
      final idx = repo.index;
      try {
        if (stageAllBeforeCommit) {
          idx.addAll(const ['*']);
          idx.write();
        }

        final treeOid = idx.writeTree();
        final tree = Tree.lookup(repo: repo, oid: treeOid);

        Signature? sig;
        try {
          if (author != null) {
            sig = Signature.create(
              name: author.name,
              email: author.email,
              time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            );
          } else {
            sig = Signature.defaultSignature(repo);
          }
        } catch (_) {
          sig = Signature.create(
            name: GitAuthor.defaultAuthor.name,
            email: GitAuthor.defaultAuthor.email,
            time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );
        }

        final parents = <Commit>[];
        if (!repo.isBranchUnborn) {
          try {
            final headRef = repo.head;
            final headCommit = Commit.lookup(repo: repo, oid: headRef.target);
            if (amend) {
              for (final parentOid in headCommit.parents) {
                parents.add(Commit.lookup(repo: repo, oid: parentOid));
              }
            } else {
              parents.add(headCommit);
            }
            headRef.free();
          } catch (_) {}
        }

        final commitOid = Commit.create(
          repo: repo,
          updateRef: 'HEAD',
          author: sig,
          committer: sig,
          message: message,
          tree: tree,
          parents: parents,
        );

        final sha = commitOid.sha;

        for (final p in parents) {
          p.free();
        }
        sig.free();
        tree.free();

        return sha;
      } finally {
        idx.free();
        repo.free();
      }
    });
  }

  /// Retrieves paginated commit history.
  Future<List<GitCommitSummary>> getCommits(
    String repoPath, {
    int limit = 50,
    int skip = 0,
    String? branchOrRef,
  }) async {
    return Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        if (repo.isBranchUnborn) {
          return const <GitCommitSummary>[];
        }

        Oid startOid;
        if (branchOrRef != null && branchOrRef.isNotEmpty) {
          final target = repo.branches.firstWhere(
            (b) => b.name == branchOrRef,
            orElse: () => repo.branches.first,
          );
          startOid = target.target;
        } else {
          final head = repo.head;
          startOid = head.target;
          head.free();
        }

        final allCommits = repo.log(oid: startOid);
        final selected = allCommits.skip(skip).take(limit).toList();

        final summaries = <GitCommitSummary>[];
        for (final c in selected) {
          final author = c.author;
          summaries.add(
            GitCommitSummary(
              sha: c.oid.sha,
              shortSha: c.oid.sha.substring(0, 7),
              summary: c.summary,
              authorName: author.name,
              authorEmail: author.email,
              time: DateTime.fromMillisecondsSinceEpoch(c.time * 1000),
              parentCount: c.parents.length,
              parentShas: c.parents.map((p) => p.sha).toList(),
            ),
          );
          author.free();
        }

        for (final c in allCommits) {
          c.free();
        }

        return summaries;
      } finally {
        repo.free();
      }
    });
  }

  /// Retrieves full commit details including diff statistics.
  Future<GitCommitDetail?> getCommitDetails(String repoPath, String sha) async {
    return Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final commitOid = repo[sha];
        final commit = Commit.lookup(repo: repo, oid: commitOid);
        final author = commit.author;
        final committer = commit.committer;

        int filesChanged = 0;
        int insertions = 0;
        int deletions = 0;

        try {
          final commitTree = Tree.lookup(repo: repo, oid: commit.treeOid);
          Tree? parentTree;
          if (commit.parents.isNotEmpty) {
            final parentCommit = Commit.lookup(
              repo: repo,
              oid: commit.parents.first,
            );
            parentTree = Tree.lookup(repo: repo, oid: parentCommit.treeOid);
            parentCommit.free();
          }

          final diff = Diff.treeToTree(
            repo: repo,
            oldTree: parentTree,
            newTree: commitTree,
          );
          final stats = diff.stats;
          filesChanged = stats.filesChanged;
          insertions = stats.insertions;
          deletions = stats.deletions;

          diff.free();
          parentTree?.free();
          commitTree.free();
        } catch (_) {}

        final detail = GitCommitDetail(
          sha: commit.oid.sha,
          summary: commit.summary,
          message: commit.message,
          authorName: author.name,
          authorEmail: author.email,
          committerName: committer.name,
          committerEmail: committer.email,
          time: DateTime.fromMillisecondsSinceEpoch(commit.time * 1000),
          parentShas: commit.parents.map((p) => p.sha).toList(),
          filesChanged: filesChanged,
          insertions: insertions,
          deletions: deletions,
        );

        committer.free();
        author.free();
        commit.free();

        return detail;
      } catch (_) {
        return null;
      } finally {
        repo.free();
      }
    });
  }

  // ===========================================================================
  // Branch Management (switch, create, delete, rename, upstream)
  // ===========================================================================

  /// Returns list of all branches (local and remote tracking).
  Future<List<GitBranchData>> getBranches(String repoPath) async {
    return Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final currentBranchName = repo.isBranchUnborn ? null : repo.head.shorthand;
        final branches = <GitBranchData>[];

        for (final b in repo.branches) {
          int ahead = 0;
          int behind = 0;
          String? upName;

          try {
            final up = b.upstream;
            upName = up.shorthand;
            final counts = repo.aheadBehind(
              local: b.target,
              upstream: up.target,
            );
            ahead = counts[0];
            behind = counts[1];
            up.free();
          } catch (_) {}

          bool isRemote = false;
          try {
            b.remoteName;
            isRemote = true;
          } catch (_) {}

          branches.add(
            GitBranchData(
              name: b.name,
              shorthand: b.name,
              isCurrent: b.name == currentBranchName,
              isRemote: isRemote,
              targetSha: b.target.sha,
              upstreamName: upName,
              ahead: ahead,
              behind: behind,
            ),
          );
          b.free();
        }

        branches.sort((a, b) {
          if (a.isCurrent) return -1;
          if (b.isCurrent) return 1;
          return a.name.compareTo(b.name);
        });

        return branches;
      } finally {
        repo.free();
      }
    });
  }

  /// Creates a new branch pointing to HEAD or [targetSha].
  Future<void> createBranch(
    String repoPath, {
    required String name,
    String? targetSha,
    bool checkout = false,
  }) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final oid = targetSha != null ? repo[targetSha] : repo.head.target;
        final targetCommit = Commit.lookup(repo: repo, oid: oid);
        final branch = Branch.create(
          repo: repo,
          name: name,
          target: targetCommit,
        );
        branch.free();
        targetCommit.free();

        if (checkout) {
          final refName = 'refs/heads/$name';
          Checkout.reference(
            repo: repo,
            name: refName,
            strategy: const {GitCheckout.safe},
          );
          repo.setHead(refName);
        }
      } finally {
        repo.free();
      }
    });
  }

  /// Checks out a branch or ref (`git checkout <branch>`).
  Future<void> checkout(
    String repoPath, {
    required String branchOrRef,
    bool createBranch = false,
    bool force = false,
  }) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final refName = branchOrRef.startsWith('refs/')
            ? branchOrRef
            : 'refs/heads/$branchOrRef';

        if (createBranch) {
          final headCommit = Commit.lookup(repo: repo, oid: repo.head.target);
          final branch = Branch.create(
            repo: repo,
            name: branchOrRef,
            target: headCommit,
          );
          branch.free();
          headCommit.free();
        }

        Checkout.reference(
          repo: repo,
          name: refName,
          strategy: force
              ? const {GitCheckout.force}
              : const {GitCheckout.safe},
        );
        repo.setHead(refName);
      } finally {
        repo.free();
      }
    });
  }

  /// Deletes a branch (`git branch -d <branch>`).
  Future<void> deleteBranch(
    String repoPath, {
    required String name,
    bool force = false,
  }) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        Branch.delete(repo: repo, name: name);
      } finally {
        repo.free();
      }
    });
  }

  /// Renames a branch (`git branch -m <oldName> <newName>`).
  Future<void> renameBranch(
    String repoPath, {
    required String oldName,
    required String newName,
    bool force = false,
  }) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        Branch.rename(
          repo: repo,
          oldName: oldName,
          newName: newName,
          force: force,
        );
      } finally {
        repo.free();
      }
    });
  }

  /// Sets upstream branch tracking (`git branch -u <upstream> <branch>`).
  Future<void> setUpstream(
    String repoPath, {
    required String branchName,
    String? upstreamName,
  }) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        for (final b in repo.branches) {
          if (b.name == branchName) {
            b.setUpstream(upstreamName);
            b.free();
            break;
          }
          b.free();
        }
      } finally {
        repo.free();
      }
    });
  }

  // ===========================================================================
  // Remotes & Remote Operations (fetch, pull, push)
  // ===========================================================================

  /// Returns list of remotes.
  Future<List<GitRemote>> getRemotes(String repoPath) async {
    return Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final remotes = <GitRemote>[];
        for (final name in repo.remotes) {
          final remote = Remote.lookup(repo: repo, name: name);
          remotes.add(
            GitRemote(
              name: remote.name,
              fetchUrl: remote.url,
              pushUrl: remote.pushUrl.isEmpty ? remote.url : remote.pushUrl,
            ),
          );
          remote.free();
        }
        return remotes;
      } finally {
        repo.free();
      }
    });
  }

  /// Adds a remote (`git remote add <name> <url>`).
  Future<void> addRemote(
    String repoPath, {
    required String name,
    required String url,
  }) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final remote = Remote.create(repo: repo, name: name, url: url);
        remote.free();
      } finally {
        repo.free();
      }
    });
  }

  /// Removes a remote (`git remote remove <name>`).
  Future<void> removeRemote(String repoPath, {required String name}) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        Remote.delete(repo: repo, name: name);
      } finally {
        repo.free();
      }
    });
  }

  /// Fetches from remote (`git fetch <remote>`).
  Future<void> fetch(
    String repoPath, {
    String remote = 'origin',
    AuthSpec? authSpec,
  }) async {
    final spec = authSpec ?? const AuthSpec.none();
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final rem = Remote.lookup(repo: repo, name: remote);
        rem.fetch(
          callbacks: spec.toCallbacks(),
          refspecs: ['+refs/heads/*:refs/remotes/$remote/*'],
        );
        rem.free();
      } finally {
        repo.free();
      }
    });
  }

  /// Pulls from remote into current branch (`git pull <remote> <branch>`).
  Future<void> pull(
    String repoPath, {
    String remote = 'origin',
    String? branch,
    AuthSpec? authSpec,
    GitAuthor? author,
  }) async {
    final spec = authSpec ?? const AuthSpec.none();
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final targetBranch = branch ?? repo.head.shorthand;
        final rem = Remote.lookup(repo: repo, name: remote);
        rem.fetch(
          callbacks: spec.toCallbacks(),
          refspecs: ['+refs/heads/*:refs/remotes/$remote/*'],
        );
        rem.free();

        final remoteRefName = 'refs/remotes/$remote/$targetBranch';
        Reference? remoteRef;
        try {
          remoteRef = Reference.lookup(repo: repo, name: remoteRefName);
        } catch (_) {}

        if (remoteRef != null) {
          final annotated = AnnotatedCommit.lookup(
            repo: repo,
            oid: remoteRef.target,
          );
          Merge.commit(repo: repo, commit: annotated);
          annotated.free();
          remoteRef.free();

          final idx = repo.index;
          if (idx.hasConflicts) {
            idx.free();
            return;
          }

          final treeOid = idx.writeTree();
          final tree = Tree.lookup(repo: repo, oid: treeOid);
          idx.free();

          final sig = Signature.defaultSignature(repo);
          final headCommit = Commit.lookup(repo: repo, oid: repo.head.target);
          final remoteCommit = Commit.lookup(
            repo: repo,
            oid: repo[remoteRefName],
          );

          Commit.create(
            repo: repo,
            updateRef: 'HEAD',
            author: sig,
            committer: sig,
            message: 'Merge remote-tracking branch $remote/$targetBranch',
            tree: tree,
            parents: [headCommit, remoteCommit],
          );

          repo.stateCleanup();
          sig.free();
          headCommit.free();
          remoteCommit.free();
          tree.free();
        }
      } finally {
        repo.free();
      }
    });
  }

  /// Pushes current branch to remote (`git push <remote> <branch>`).
  Future<void> push(
    String repoPath, {
    String remote = 'origin',
    String? branch,
    bool setUpstream = false,
    bool force = false,
    AuthSpec? authSpec,
  }) async {
    final spec = authSpec ?? const AuthSpec.none();
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final targetBranch = branch ?? repo.head.shorthand;
        final rem = Remote.lookup(repo: repo, name: remote);
        final refspec = force
            ? '+refs/heads/$targetBranch:refs/heads/$targetBranch'
            : 'refs/heads/$targetBranch:refs/heads/$targetBranch';

        rem.push(refspecs: [refspec], callbacks: spec.toCallbacks());
        rem.free();

        if (setUpstream) {
          for (final b in repo.branches) {
            if (b.name == targetBranch) {
              b.setUpstream('$remote/$targetBranch');
              b.free();
              break;
            }
            b.free();
          }
        }
      } finally {
        repo.free();
      }
    });
  }

  // ===========================================================================
  // Stash Management (save, pop, apply, drop, list)
  // ===========================================================================

  /// Returns list of saved stashes.
  Future<List<GitStashData>> getStashes(String repoPath) async {
    return Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final rawStashes = Stash.list(repo);
        return rawStashes
            .map(
              (s) => GitStashData(
                index: s.index,
                message: s.message,
                sha: s.oid.sha,
              ),
            )
            .toList();
      } finally {
        repo.free();
      }
    });
  }

  /// Saves current changes to stash (`git stash save`).
  Future<String> saveStash(
    String repoPath, {
    String? message,
    bool includeUntracked = false,
    GitAuthor? author,
  }) async {
    return Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        Signature? sig;
        try {
          if (author != null) {
            sig = Signature.create(
              name: author.name,
              email: author.email,
              time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            );
          } else {
            sig = Signature.defaultSignature(repo);
          }
        } catch (_) {
          sig = Signature.create(
            name: GitAuthor.defaultAuthor.name,
            email: GitAuthor.defaultAuthor.email,
            time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );
        }

        final stashOid = Stash.create(
          repo: repo,
          stasher: sig,
          message: message,
          flags: includeUntracked ? {GitStash.includeUntracked} : {},
        );

        final sha = stashOid.sha;
        sig.free();
        return sha;
      } finally {
        repo.free();
      }
    });
  }

  /// Pops stash entry at [index] (`git stash pop stash@{index}`).
  Future<void> popStash(String repoPath, {int index = 0}) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        Stash.pop(repo: repo, index: index);
      } finally {
        repo.free();
      }
    });
  }

  /// Applies stash entry at [index] (`git stash apply stash@{index}`).
  Future<void> applyStash(String repoPath, {int index = 0}) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        Stash.apply(repo: repo, index: index);
      } finally {
        repo.free();
      }
    });
  }

  /// Drops stash entry at [index] (`git stash drop stash@{index}`).
  Future<void> dropStash(String repoPath, {int index = 0}) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        Stash.drop(repo: repo, index: index);
      } finally {
        repo.free();
      }
    });
  }

  /// Clears all stashes.
  Future<void> clearStashes(String repoPath) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final stashes = Stash.list(repo);
        for (int i = stashes.length - 1; i >= 0; i--) {
          Stash.drop(repo: repo, index: i);
        }
      } finally {
        repo.free();
      }
    });
  }

  // ===========================================================================
  // Tag Management
  // ===========================================================================

  /// Returns list of tags.
  Future<List<GitTagData>> getTags(String repoPath) async {
    return Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final tagNames = Tag.list(repo: repo);
        final tags = <GitTagData>[];

        for (final name in tagNames) {
          try {
            final tagRef = Reference.lookup(repo: repo, name: 'refs/tags/$name');
            tags.add(
              GitTagData(
                name: name,
                targetSha: tagRef.target.sha,
              ),
            );
            tagRef.free();
          } catch (_) {}
        }
        return tags;
      } finally {
        repo.free();
      }
    });
  }

  /// Creates a tag (`git tag <name>`).
  Future<void> createTag(
    String repoPath, {
    required String name,
    String? targetSha,
    String? message,
    GitAuthor? author,
  }) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final targetOid = targetSha != null ? repo[targetSha] : repo.head.target;
        if (message != null && message.isNotEmpty) {
          Signature? sig;
          try {
            sig = author != null
                ? Signature.create(
                    name: author.name,
                    email: author.email,
                    time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  )
                : Signature.defaultSignature(repo);
          } catch (_) {
            sig = Signature.create(
              name: GitAuthor.defaultAuthor.name,
              email: GitAuthor.defaultAuthor.email,
              time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            );
          }
          Tag.createAnnotated(
            repo: repo,
            tagName: name,
            target: targetOid,
            targetType: GitObject.commit,
            tagger: sig,
            message: message,
          );
          sig.free();
        } else {
          Tag.createLightweight(
            repo: repo,
            tagName: name,
            target: targetOid,
            targetType: GitObject.commit,
          );
        }
      } finally {
        repo.free();
      }
    });
  }

  /// Deletes a tag (`git tag -d <name>`).
  Future<void> deleteTag(String repoPath, {required String name}) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        Tag.delete(repo: repo, tagName: name);
      } finally {
        repo.free();
      }
    });
  }

  // ===========================================================================
  // Diffs & File Inspection
  // ===========================================================================

  /// Retrieves unified diff data for [relativePath].
  /// If [staged] is true, returns diff between tree and index (`git diff --cached <file>`).
  /// If [staged] is false, returns diff between index and workdir (`git diff <file>`).
  Future<GitFileDiff> getFileDiff(
    String repoPath, {
    required String relativePath,
    bool staged = false,
  }) async {
    return Isolate.run(() {
      final repo = Repository.open(repoPath);
      final idx = repo.index;
      try {
        final normalized = relativePath.replaceAll(r'\', '/');
        final Diff diff;
        Tree? headTree;

        if (staged) {
          if (!repo.isBranchUnborn) {
            final headRef = repo.head;
            final headCommit = Commit.lookup(repo: repo, oid: headRef.target);
            headTree = Tree.lookup(repo: repo, oid: headCommit.treeOid);
            headCommit.free();
            headRef.free();
          }
          diff = Diff.treeToIndex(repo: repo, tree: headTree, index: idx);
        } else {
          diff = Diff.indexToWorkdir(repo: repo, index: idx);
        }

        GitFileDiff result = GitFileDiff.empty;
        final deltas = diff.deltas;
        for (int i = 0; i < deltas.length; i++) {
          final delta = deltas[i];
          final deltaNewFile = delta.newFile.path.replaceAll(r'\', '/');
          final deltaOldFile = delta.oldFile.path.replaceAll(r'\', '/');

          if (deltaNewFile == normalized || deltaOldFile == normalized) {
            final patch = Patch.fromDiff(diff: diff, index: i);
            final stats = patch.stats;
            final patchText = patch.text;

            final hunks = <GitDiffHunk>[];
            for (final h in patch.hunks) {
              final lines = <GitDiffLineData>[];
              for (final l in h.lines) {
                final type = switch (l.origin) {
                  GitDiffLine.addition => GitDiffLineType.addition,
                  GitDiffLine.deletion => GitDiffLineType.deletion,
                  _ => GitDiffLineType.context,
                };
                lines.add(
                  GitDiffLineData(
                    type: type,
                    content: l.content,
                    oldLineNumber: l.oldLineNumber == -1 ? null : l.oldLineNumber,
                    newLineNumber: l.newLineNumber == -1 ? null : l.newLineNumber,
                  ),
                );
              }
              hunks.add(
                GitDiffHunk(
                  oldStart: h.oldStart,
                  oldLines: h.oldLines,
                  newStart: h.newStart,
                  newLines: h.newLines,
                  header: h.header,
                  lines: lines,
                ),
              );
            }

            result = GitFileDiff(
              oldPath: deltaOldFile,
              newPath: deltaNewFile,
              isNew: delta.status == GitDelta.added,
              isDeleted: delta.status == GitDelta.deleted,
              isRenamed: delta.status == GitDelta.renamed,
              patchText: patchText,
              additions: stats.insertions,
              deletions: stats.deletions,
              hunks: hunks,
            );

            patch.free();
            break;
          }
        }

        diff.free();
        headTree?.free();
        return result;
      } finally {
        idx.free();
        repo.free();
      }
    });
  }

  /// Returns file content at a specific commit/ref or index.
  Future<String?> getFileContentAtRef(
    String repoPath, {
    required String relativePath,
    String? refOrCommitSha,
    bool fromIndex = false,
  }) async {
    return Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final normalized = relativePath.replaceAll(r'\', '/');

        if (fromIndex) {
          final idx = repo.index;
          try {
            IndexEntry? entry;
            try {
              entry = idx[normalized];
            } catch (_) {
              entry = null;
            }
            if (entry == null) return null;
            final blob = Blob.lookup(repo: repo, oid: entry.oid);
            final content = blob.content;
            blob.free();
            return content;
          } finally {
            idx.free();
          }
        }

        if (refOrCommitSha != null && refOrCommitSha.isNotEmpty) {
          final oid = repo[refOrCommitSha];
          final commit = Commit.lookup(repo: repo, oid: oid);
          final tree = Tree.lookup(repo: repo, oid: commit.treeOid);
          TreeEntry? entry;
          try {
            entry = tree[normalized];
          } catch (_) {
            entry = null;
          }
          if (entry == null) {
            tree.free();
            commit.free();
            return null;
          }
          final blob = Blob.lookup(repo: repo, oid: entry.oid);
          final content = blob.content;
          blob.free();
          tree.free();
          commit.free();
          return content;
        }

        if (repo.isBranchUnborn) return null;
        final headRef = repo.head;
        final commit = Commit.lookup(repo: repo, oid: headRef.target);
        final tree = Tree.lookup(repo: repo, oid: commit.treeOid);
        TreeEntry? entry;
        try {
          entry = tree[normalized];
        } catch (_) {
          entry = null;
        }
        headRef.free();
        if (entry == null) {
          tree.free();
          commit.free();
          return null;
        }
        final blob = Blob.lookup(repo: repo, oid: entry.oid);
        final content = blob.content;
        blob.free();
        tree.free();
        commit.free();
        return content;
      } catch (_) {
        return null;
      } finally {
        repo.free();
      }
    });
  }

  // ===========================================================================
  // Merging & Conflict Resolution
  // ===========================================================================

  /// Merges a branch or ref into current HEAD.
  Future<void> merge(
    String repoPath, {
    required String branchOrRef,
    GitAuthor? author,
  }) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final targetOid = repo[branchOrRef];
        final annotated = AnnotatedCommit.lookup(repo: repo, oid: targetOid);
        Merge.commit(repo: repo, commit: annotated);
        annotated.free();

        final idx = repo.index;
        if (idx.hasConflicts) {
          idx.free();
          return;
        }

        final treeOid = idx.writeTree();
        final tree = Tree.lookup(repo: repo, oid: treeOid);
        idx.free();

        Signature? sig;
        try {
          sig = author != null
              ? Signature.create(
                  name: author.name,
                  email: author.email,
                  time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                )
              : Signature.defaultSignature(repo);
        } catch (_) {
          sig = Signature.create(
            name: GitAuthor.defaultAuthor.name,
            email: GitAuthor.defaultAuthor.email,
            time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );
        }

        final headCommit = Commit.lookup(repo: repo, oid: repo.head.target);
        final theirCommit = Commit.lookup(repo: repo, oid: targetOid);

        Commit.create(
          repo: repo,
          updateRef: 'HEAD',
          author: sig,
          committer: sig,
          message: 'Merge $branchOrRef',
          tree: tree,
          parents: [headCommit, theirCommit],
        );

        repo.stateCleanup();
        sig.free();
        headCommit.free();
        theirCommit.free();
        tree.free();
      } finally {
        repo.free();
      }
    });
  }

  /// Aborts an in-progress merge.
  Future<void> abortMerge(String repoPath) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        if (!repo.isBranchUnborn) {
          repo.reset(oid: repo.head.target, resetType: GitReset.hard);
        }
        repo.stateCleanup();
      } finally {
        repo.free();
      }
    });
  }

  /// Resolves a merge conflict on [relativePath] by picking "ours" or "theirs".
  Future<void> resolveConflict(
    String repoPath, {
    required String relativePath,
    required bool useOurs,
  }) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      final idx = repo.index;
      try {
        final normalized = relativePath.replaceAll(r'\', '/');
        Checkout.index(
          repo: repo,
          paths: [normalized],
          strategy: useOurs
              ? const {GitCheckout.safe, GitCheckout.useOurs}
              : const {GitCheckout.safe, GitCheckout.useTheirs},
        );
        idx.add(normalized);
        idx.write();
      } finally {
        idx.free();
        repo.free();
      }
    });
  }

  // ===========================================================================
  // Ignore & Config
  // ===========================================================================

  /// Checks if [relativePath] is ignored by `.gitignore`.
  Future<bool> isPathIgnored(String repoPath, String relativePath) async {
    return Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        return Ignore.pathIsIgnored(repo: repo, path: relativePath);
      } catch (_) {
        return false;
      } finally {
        repo.free();
      }
    });
  }

  /// Appends [pattern] to `.gitignore` at repository root.
  Future<void> addToGitignore(String repoPath, String pattern) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final gitignore = File(p.join(repo.workdir, '.gitignore'));
        if (!gitignore.existsSync()) {
          gitignore.createSync(recursive: true);
        }
        gitignore.writeAsStringSync('$pattern\n', mode: FileMode.append);
      } finally {
        repo.free();
      }
    });
  }

  /// Reads a Git config key.
  Future<String?> getConfig(String repoPath, String key) async {
    return Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final config = repo.config;
        return config[key].value;
      } catch (_) {
        return null;
      } finally {
        repo.free();
      }
    });
  }

  /// Writes a Git config key.
  Future<void> setConfig(String repoPath, String key, String value) async {
    await Isolate.run(() {
      final repo = Repository.open(repoPath);
      try {
        final config = repo.config;
        config[key] = value;
      } finally {
        repo.free();
      }
    });
  }

  /// Retrieves runtime platform diagnostics for libgit2.
  Future<PlatformDiagnostics> getDiagnostics([String? storagePath]) async {
    return Isolate.run(() {
      String label = Platform.operatingSystem;
      if (Platform.isAndroid) label = 'Android';
      if (Platform.isIOS) label = 'iOS';
      if (Platform.isLinux) label = 'Linux';
      if (Platform.isMacOS) label = 'macOS';
      if (Platform.isWindows) label = 'Windows';

      final notes = <String>[
        if (Platform.isWindows) '64-bit Windows libgit2 runtime',
        if (Platform.isAndroid) 'Android CA certificates configured',
        if (Platform.isIOS) 'iOS static libgit2 bindings initialized',
        if (Platform.isLinux) 'Linux desktop native runtime',
        if (Platform.isMacOS) 'macOS desktop native runtime',
      ];

      return PlatformDiagnostics(
        platformLabel: label,
        libgit2Version: Libgit2.version,
        storagePath: storagePath ?? Directory.current.path,
        platformReady: true,
        notes: notes,
      );
    });
  }
}

