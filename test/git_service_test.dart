import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fedit/models/git_models.dart';
import 'package:fedit/services/git_service.dart';
import 'package:fedit/providers/source_control_manager.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late GitService gitService;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('git_service_test_');
    gitService = const GitService();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('GitService standalone background methods', () {
    test('init, detect, and find root', () async {
      expect(await gitService.isRepository(tempDir.path), false);
      expect(await gitService.findRepositoryRoot(tempDir.path), isNull);

      await gitService.initRepository(
        path: tempDir.path,
        initialHead: 'main',
        author: const GitAuthor(name: 'Dev', email: 'dev@test.local'),
      );

      expect(await gitService.isRepository(tempDir.path), true);
      final foundRoot = await gitService.findRepositoryRoot(tempDir.path);
      expect(foundRoot, isNotNull);
      expect(foundRoot!.toLowerCase(), tempDir.path.replaceAll(r'\', '/').toLowerCase());
    });

    test('full staging, unstaging, committing and status lifecycle', () async {
      await gitService.initRepository(path: tempDir.path, initialHead: 'main');

      // Create files
      final f1 = File(p.join(tempDir.path, 'file1.txt'))..writeAsStringSync('line 1\n');
      final f2 = File(p.join(tempDir.path, 'file2.txt'))..writeAsStringSync('line 2\n');

      var status = await gitService.getStatus(tempDir.path);
      expect(status.untrackedChanges.length, 2);
      expect(status.stagedChanges.isEmpty, true);
      expect(status.workingTreeChanges.isEmpty, true);

      // Stage file1
      await gitService.stageFile(tempDir.path, 'file1.txt');
      status = await gitService.getStatus(tempDir.path);
      expect(status.stagedChanges.length, 1);
      expect(status.stagedChanges.first.path, 'file1.txt');
      expect(status.untrackedChanges.length, 1);
      expect(status.untrackedChanges.first.path, 'file2.txt');

      // Unstage file1
      await gitService.unstageFile(tempDir.path, 'file1.txt');
      status = await gitService.getStatus(tempDir.path);
      expect(status.stagedChanges.isEmpty, true);

      // Stage all
      await gitService.stageAll(tempDir.path);
      status = await gitService.getStatus(tempDir.path);
      expect(status.stagedChanges.length, 2);

      // Commit
      final sha = await gitService.commit(
        tempDir.path,
        message: 'Initial commit',
        author: const GitAuthor(name: 'Dev', email: 'dev@test.local'),
      );
      expect(sha.isNotEmpty, true);

      status = await gitService.getStatus(tempDir.path);
      expect(status.isClean, true);
      expect(status.headSha, sha);

      // Modify file1 and delete file2
      f1.writeAsStringSync('line 1 modified\n');
      f2.deleteSync();

      status = await gitService.getStatus(tempDir.path);
      expect(status.workingTreeChanges.length, 2);
      final mod = status.workingTreeChanges.firstWhere((c) => c.path == 'file1.txt');
      final del = status.workingTreeChanges.firstWhere((c) => c.path == 'file2.txt');
      expect(mod.status, GitFileDeltaStatus.modified);
      expect(del.status, GitFileDeltaStatus.deleted);

      // Stage modified and deleted
      await gitService.stageFiles(tempDir.path, ['file1.txt', 'file2.txt']);
      status = await gitService.getStatus(tempDir.path);
      expect(status.stagedChanges.length, 2);
      expect(status.workingTreeChanges.isEmpty, true);

      // Unstage all
      await gitService.unstageAll(tempDir.path);
      status = await gitService.getStatus(tempDir.path);
      expect(status.stagedChanges.isEmpty, true);
      expect(status.workingTreeChanges.length, 2);

      // Discard all changes
      await gitService.discardAll(tempDir.path);
      status = await gitService.getStatus(tempDir.path);
      expect(status.isClean, true);
      expect(f2.existsSync(), true);
      expect(f1.readAsStringSync(), 'line 1\n');
    });

    test('branch management', () async {
      await gitService.initRepository(path: tempDir.path, initialHead: 'main');
      File(p.join(tempDir.path, 'README.md')).writeAsStringSync('test');
      await gitService.stageAll(tempDir.path);
      await gitService.commit(tempDir.path, message: 'init');

      await gitService.createBranch(tempDir.path, name: 'feature/login', checkout: true);
      var branches = await gitService.getBranches(tempDir.path);
      expect(branches.length, 2);
      final active = branches.firstWhere((b) => b.isCurrent);
      expect(active.name, 'feature/login');

      // Switch back
      await gitService.checkout(tempDir.path, branchOrRef: 'main');
      branches = await gitService.getBranches(tempDir.path);
      expect(branches.firstWhere((b) => b.isCurrent).name, 'main');

      // Delete feature branch
      await gitService.deleteBranch(tempDir.path, name: 'feature/login');
      branches = await gitService.getBranches(tempDir.path);
      expect(branches.any((b) => b.name == 'feature/login'), false);
    });

    test('stash and diff data', () async {
      await gitService.initRepository(path: tempDir.path, initialHead: 'main');
      final f = File(p.join(tempDir.path, 'code.dart'))..writeAsStringSync('void main() {}\n');
      await gitService.stageAll(tempDir.path);
      await gitService.commit(tempDir.path, message: 'init');

      f.writeAsStringSync('void main() { print("hello"); }\n');

      // Diff check
      final diff = await gitService.getFileDiff(tempDir.path, relativePath: 'code.dart');
      expect(diff.patchText, contains('print("hello")'));
      expect(diff.additions, 1);
      expect(diff.deletions, 1);

      // Stash
      final stashSha = await gitService.saveStash(tempDir.path, message: 'WIP print');
      expect(stashSha.isNotEmpty, true);

      var stashes = await gitService.getStashes(tempDir.path);
      expect(stashes.length, 1);
      expect(f.readAsStringSync(), 'void main() {}\n');

      // Pop stash
      await gitService.popStash(tempDir.path, index: 0);
      stashes = await gitService.getStashes(tempDir.path);
      expect(stashes.isEmpty, true);
      expect(f.readAsStringSync(), 'void main() { print("hello"); }\n');
    });
  });

  group('SourceControlManager (VS Code State Manager)', () {
    test('workspace tracking and reactive actions', () async {
      final scm = SourceControlManager(gitService: gitService);

      await scm.openWorkspace(tempDir.path);
      expect(scm.isRepo, false);

      await scm.initRepository(initialHead: 'main');
      expect(scm.isRepo, true);
      expect(scm.isClean, true);

      // Create new file
      File(p.join(tempDir.path, 'app.dart')).writeAsStringSync('class App {}\n');
      await scm.refresh();

      expect(scm.untrackedChanges.length, 1);
      expect(scm.stagedChanges.isEmpty, true);

      // Stage
      await scm.stage('app.dart');
      expect(scm.stagedChanges.length, 1);
      expect(scm.untrackedChanges.isEmpty, true);

      // Commit
      scm.commitMessageController.text = 'Add App class';
      await scm.commit();
      expect(scm.isClean, true);
      expect(scm.recentCommits.length, 1);
      expect(scm.recentCommits.first.summary, 'Add App class');

      // Create & switch branch
      await scm.createBranch('dev');
      expect(scm.currentBranch, 'dev');

      // Test commit and undo commit
      File(p.join(tempDir.path, 'dev.dart')).writeAsStringSync('class Dev {}\n');
      await scm.stage('dev.dart');
      await scm.commit(message: 'Commit to undo');
      expect(scm.recentCommits.first.summary, 'Commit to undo');

      await scm.undoCommit(soft: true);
      expect(scm.recentCommits.first.summary, 'Add App class');
      expect(scm.stagedChanges.any((c) => c.path == 'dev.dart'), true);

      // Test remotes
      await scm.addRemote(name: 'origin', url: 'https://github.com/example/repo.git');
      expect(scm.remotes.any((r) => r.name == 'origin'), true);

      await scm.setRemoteUrl(name: 'origin', url: 'https://github.com/example/updated.git');
      expect(scm.remotes.firstWhere((r) => r.name == 'origin').fetchUrl, 'https://github.com/example/updated.git');

      // Verify commit branch annotations
      final commitsWithTags = await gitService.getCommits(tempDir.path);
      expect(commitsWithTags.first.isHead, true);
      expect(commitsWithTags.first.branchNames.isNotEmpty, true);

      scm.dispose();
    });
  });
}

