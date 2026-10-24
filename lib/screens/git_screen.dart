import 'package:fedit/models/git_models.dart';
import 'package:fedit/providers/git_log_store.dart';
import 'package:fedit/services/git_workspace_service.dart';
import 'package:flutter/material.dart';





class Git2DartDemoHome extends StatefulWidget {
  const Git2DartDemoHome({super.key, this.workspaceService});

  final GitWorkspaceService? workspaceService;

  @override
  State<Git2DartDemoHome> createState() => _Git2DartDemoHomeState();
}

class _Git2DartDemoHomeState extends State<Git2DartDemoHome> {
  late final GitWorkspaceService _service;
  late final GitLogStore _logStore;
  late Future<void> _initialLoad;

  GitWorkspaceSnapshot _snapshot = GitWorkspaceSnapshot.empty;
  PlatformDiagnostics? _diagnostics;
  ObjectInspection? _objectInspection;
  RemoteRefsResult? _remoteRefs;
  AuthMode _authMode = AuthMode.none;
  bool _busy = false;

  final _remoteUrlController = TextEditingController(
    text: 'https://github.com/libgit2/TestGitRepository',
  );
  final _usernameController = TextEditingController(text: 'git');
  final _passwordController = TextEditingController();
  final _publicKeyPathController = TextEditingController();
  final _privateKeyPathController = TextEditingController();
  final _publicKeyController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _passphraseController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _service = widget.workspaceService ?? GitWorkspaceService();
    _logStore = GitLogStore();
    _initialLoad = _loadInitialState();
  }

  @override
  void dispose() {
    _logStore.dispose();
    _remoteUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _publicKeyPathController.dispose();
    _privateKeyPathController.dispose();
    _publicKeyController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialState() async {
    final diagnostics = await _service.diagnostics();
    final snapshot = await _service.snapshot();
    if (!mounted) {
      return;
    }
    setState(() {
      _diagnostics = diagnostics;
      _snapshot = snapshot;
    });
  }

  Future<void> _runSnapshotScenario(
    Future<GitScenarioResult<GitWorkspaceSnapshot>> Function() operation,
  ) async {
    await _run(() async {
      final result = await operation();
      _snapshot = result.value;
      _logStore.addAll(result.events);
    });
  }

  Future<void> _runObjectInspection() async {
    await _run(() async {
      final result = await _service.inspectObjects();
      _objectInspection = result.value;
      _logStore.addAll(result.events);
    });
  }

  Future<void> _runRemoteRefs() async {
    await _run(() async {
      final authSpec = _authSpecFromForm();
      if (!authSpec.isReady) {
        throw StateError('Selected auth mode is missing required fields.');
      }
      final result = await _service.listRemoteRefs(
        url: _remoteUrlController.text.trim(),
        authSpec: authSpec,
      );
      _remoteRefs = result.value;
      _logStore.addAll(result.events);
      _clearSecrets(keepUsername: true);
    });
  }

  Future<void> _refreshSnapshot() async {
    await _run(() async {
      _snapshot = await _service.snapshot();
      _logStore.addAll([GitOperationEvent.info('Refreshed snapshot')]);
    });
  }

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await body();
    } on Object catch (error) {
      _logStore.addError(error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  AuthSpec _authSpecFromForm() {
    return AuthSpec(
      mode: _authMode,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      publicKeyPath: _publicKeyPathController.text.trim(),
      privateKeyPath: _privateKeyPathController.text.trim(),
      publicKey: _publicKeyController.text,
      privateKey: _privateKeyController.text,
      passphrase: _passphraseController.text,
    );
  }

  void _clearSecrets({bool keepUsername = false}) {
    _passwordController.clear();
    _privateKeyController.clear();
    _passphraseController.clear();
    if (!keepUsername) {
      _usernameController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialLoad,
      builder: (context, snapshot) {
        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('git2dart demo console'),
              actions: [
                IconButton(
                  tooltip: 'Refresh snapshot',
                  onPressed: _busy ? null : _refreshSnapshot,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'Clear log',
                  onPressed: _logStore.clear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ],
              bottom: const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(icon: Icon(Icons.terminal), text: 'Local Git'),
                  Tab(icon: Icon(Icons.account_tree_outlined), text: 'Objects'),
                  Tab(icon: Icon(Icons.cloud_sync_outlined), text: 'Remotes'),
                  Tab(icon: Icon(Icons.devices_outlined), text: 'Platforms'),
                  Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Log'),
                ],
              ),
            ),
            body: Column(
              children: [
                _Dashboard(
                  diagnostics: _diagnostics,
                  snapshot: _snapshot,
                  busy: _busy,
                ),
                if (_busy) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: TabBarView(
                    children: [
                      _LocalGitTab(
                        snapshot: _snapshot,
                        onResetSeed: () =>
                            _runSnapshotScenario(_service.resetAndSeed),
                        onMakeChanges: () =>
                            _runSnapshotScenario(_service.makeWorkingChanges),
                        onCommit: () =>
                            _runSnapshotScenario(_service.stageAndCommit),
                        onMerge: () =>
                            _runSnapshotScenario(_service.createBranchAndMerge),
                        onStash: () =>
                            _runSnapshotScenario(_service.stashChanges),
                        onReset: () => _runSnapshotScenario(_service.hardReset),
                        onPushFetch: () => _runSnapshotScenario(
                          _service.pushAndFetchLocalRemote,
                        ),
                        busy: _busy,
                      ),
                      _ObjectsTab(
                        inspection: _objectInspection,
                        onInspect: _runObjectInspection,
                        busy: _busy,
                      ),
                      _RemotesTab(
                        authMode: _authMode,
                        remoteUrlController: _remoteUrlController,
                        usernameController: _usernameController,
                        passwordController: _passwordController,
                        publicKeyPathController: _publicKeyPathController,
                        privateKeyPathController: _privateKeyPathController,
                        publicKeyController: _publicKeyController,
                        privateKeyController: _privateKeyController,
                        passphraseController: _passphraseController,
                        refs: _remoteRefs,
                        busy: _busy,
                        onAuthModeChanged: (mode) {
                          setState(() => _authMode = mode);
                          _clearSecrets(keepUsername: true);
                        },
                        onListRefs: _runRemoteRefs,
                        onClearSecrets: () {
                          _clearSecrets();
                          setState(() {});
                        },
                      ),
                      _PlatformsTab(diagnostics: _diagnostics),
                      _LogTab(store: _logStore),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.diagnostics,
    required this.snapshot,
    required this.busy,
  });

  final PlatformDiagnostics? diagnostics;
  final GitWorkspaceSnapshot snapshot;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Metric(
            icon: Icons.memory_outlined,
            label: 'libgit2',
            value: diagnostics?.libgit2Version ?? 'loading',
          ),
          _Metric(
            icon: Icons.devices_outlined,
            label: 'platform',
            value: diagnostics?.platformLabel ?? 'loading',
          ),
          _Metric(
            icon: snapshot.isClean ? Icons.check_circle : Icons.change_circle,
            label: 'worktree',
            value: snapshot.repoPath.isEmpty
                ? 'not seeded'
                : snapshot.isClean
                ? 'clean'
                : '${snapshot.statusEntries.length} changes',
          ),
          _Metric(
            icon: Icons.commit_outlined,
            label: 'HEAD',
            value: snapshot.headSha.isEmpty
                ? 'none'
                : '${snapshot.headName} ${snapshot.headSha.substring(0, 7)}',
          ),
          _Metric(
            icon: busy ? Icons.hourglass_top : Icons.folder_outlined,
            label: 'workspace',
            value: diagnostics?.storagePath ?? '',
            wide: true,
          ),
        ],
      ),
    );
  }
}

class _LocalGitTab extends StatelessWidget {
  const _LocalGitTab({
    required this.snapshot,
    required this.onResetSeed,
    required this.onMakeChanges,
    required this.onCommit,
    required this.onMerge,
    required this.onStash,
    required this.onReset,
    required this.onPushFetch,
    required this.busy,
  });

  final GitWorkspaceSnapshot snapshot;
  final VoidCallback onResetSeed;
  final VoidCallback onMakeChanges;
  final VoidCallback onCommit;
  final VoidCallback onMerge;
  final VoidCallback onStash;
  final VoidCallback onReset;
  final VoidCallback onPushFetch;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return _ScrollableTab(
      children: [
        _Section(
          title: 'Offline Scenarios',
          icon: Icons.terminal,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CommandButton(
                icon: Icons.restart_alt,
                label: 'Reset + seed',
                onPressed: busy ? null : onResetSeed,
              ),
              _CommandButton(
                icon: Icons.edit_document,
                label: 'Make changes',
                onPressed: busy || snapshot.repoPath.isEmpty
                    ? null
                    : onMakeChanges,
              ),
              _CommandButton(
                icon: Icons.add_task,
                label: 'Stage + commit',
                onPressed: busy || snapshot.repoPath.isEmpty ? null : onCommit,
              ),
              _CommandButton(
                icon: Icons.merge_type,
                label: 'Branch + merge',
                onPressed: busy || snapshot.repoPath.isEmpty ? null : onMerge,
              ),
              _CommandButton(
                icon: Icons.archive_outlined,
                label: 'Stash edit',
                onPressed: busy || snapshot.repoPath.isEmpty ? null : onStash,
              ),
              _CommandButton(
                icon: Icons.settings_backup_restore,
                label: 'Hard reset',
                onPressed: busy || snapshot.repoPath.isEmpty ? null : onReset,
              ),
              _CommandButton(
                icon: Icons.sync_alt,
                label: 'Push/fetch local',
                onPressed: busy || snapshot.repoPath.isEmpty
                    ? null
                    : onPushFetch,
              ),
            ],
          ),
        ),
        _Section(
          title: 'Repository Snapshot',
          icon: Icons.folder_copy_outlined,
          child: _SnapshotView(snapshot: snapshot),
        ),
        _Section(
          title: 'Status',
          icon: Icons.fact_check_outlined,
          child: snapshot.statusEntries.isEmpty
              ? const Text('Working tree is clean.')
              : _StatusList(entries: snapshot.statusEntries),
        ),
        _Section(
          title: 'Recent Commits',
          icon: Icons.history,
          child: snapshot.commits.isEmpty
              ? const Text('No commits yet.')
              : _CommitList(commits: snapshot.commits),
        ),
      ],
    );
  }
}

class _ObjectsTab extends StatelessWidget {
  const _ObjectsTab({
    required this.inspection,
    required this.onInspect,
    required this.busy,
  });

  final ObjectInspection? inspection;
  final VoidCallback onInspect;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return _ScrollableTab(
      children: [
        _Section(
          title: 'Object Database',
          icon: Icons.account_tree_outlined,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CommandButton(
                icon: Icons.search,
                label: 'Inspect objects',
                onPressed: busy ? null : onInspect,
              ),
            ],
          ),
        ),
        if (inspection != null)
          _Section(
            title: 'Inspection Result',
            icon: Icons.data_object,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _KeyValue(label: 'README hash', value: inspection!.fileHash),
                _KeyValue(label: 'Created blob', value: inspection!.blobSha),
                _KeyValue(label: 'HEAD tree', value: inspection!.headTreeSha),
                const SizedBox(height: 12),
                const Text('Blob content'),
                _MonoBlock(inspection!.blobContent),
                const SizedBox(height: 12),
                const Text('Index to workdir patch'),
                _MonoBlock(
                  inspection!.diffPatch.isEmpty
                      ? '(no unstaged diff)'
                      : inspection!.diffPatch,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RemotesTab extends StatelessWidget {
  const _RemotesTab({
    required this.authMode,
    required this.remoteUrlController,
    required this.usernameController,
    required this.passwordController,
    required this.publicKeyPathController,
    required this.privateKeyPathController,
    required this.publicKeyController,
    required this.privateKeyController,
    required this.passphraseController,
    required this.refs,
    required this.busy,
    required this.onAuthModeChanged,
    required this.onListRefs,
    required this.onClearSecrets,
  });

  final AuthMode authMode;
  final TextEditingController remoteUrlController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController publicKeyPathController;
  final TextEditingController privateKeyPathController;
  final TextEditingController publicKeyController;
  final TextEditingController privateKeyController;
  final TextEditingController passphraseController;
  final RemoteRefsResult? refs;
  final bool busy;
  final ValueChanged<AuthMode> onAuthModeChanged;
  final VoidCallback onListRefs;
  final VoidCallback onClearSecrets;

  @override
  Widget build(BuildContext context) {
    return _ScrollableTab(
      children: [
        _Section(
          title: 'Remote Probe',
          icon: Icons.cloud_sync_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: remoteUrlController,
                decoration: const InputDecoration(
                  labelText: 'Remote URL',
                  prefixIcon: Icon(Icons.link),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AuthMode>(
                initialValue: authMode,
                decoration: const InputDecoration(
                  labelText: 'Auth mode',
                  prefixIcon: Icon(Icons.key_outlined),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: AuthMode.none,
                    child: Text('No credentials'),
                  ),
                  DropdownMenuItem(
                    value: AuthMode.httpsUserPass,
                    child: Text('HTTPS user/password'),
                  ),
                  DropdownMenuItem(
                    value: AuthMode.sshKeyFiles,
                    child: Text('SSH key files'),
                  ),
                  DropdownMenuItem(
                    value: AuthMode.sshKeyMemory,
                    child: Text('SSH key from memory'),
                  ),
                  DropdownMenuItem(
                    value: AuthMode.sshAgent,
                    child: Text('SSH agent'),
                  ),
                ],
                onChanged: (mode) {
                  if (mode != null) {
                    onAuthModeChanged(mode);
                  }
                },
              ),
              const SizedBox(height: 12),
              _AuthFields(
                mode: authMode,
                usernameController: usernameController,
                passwordController: passwordController,
                publicKeyPathController: publicKeyPathController,
                privateKeyPathController: privateKeyPathController,
                publicKeyController: publicKeyController,
                privateKeyController: privateKeyController,
                passphraseController: passphraseController,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CommandButton(
                    icon: Icons.list_alt,
                    label: 'List refs',
                    onPressed: busy ? null : onListRefs,
                  ),
                  _CommandButton(
                    icon: Icons.cleaning_services_outlined,
                    label: 'Clear secrets',
                    onPressed: onClearSecrets,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Secrets stay in memory only and are cleared after remote operations.',
              ),
            ],
          ),
        ),
        if (refs != null)
          _Section(
            title: 'Remote Refs',
            icon: Icons.format_list_bulleted,
            child: _RemoteRefsList(refs: refs!.refs),
          ),
      ],
    );
  }
}

class _AuthFields extends StatelessWidget {
  const _AuthFields({
    required this.mode,
    required this.usernameController,
    required this.passwordController,
    required this.publicKeyPathController,
    required this.privateKeyPathController,
    required this.publicKeyController,
    required this.privateKeyController,
    required this.passphraseController,
  });

  final AuthMode mode;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController publicKeyPathController;
  final TextEditingController privateKeyPathController;
  final TextEditingController publicKeyController;
  final TextEditingController privateKeyController;
  final TextEditingController passphraseController;

  @override
  Widget build(BuildContext context) {
    if (mode == AuthMode.none) {
      return const Text('Public remotes can be queried without credentials.');
    }

    final fields = <Widget>[
      TextField(
        controller: usernameController,
        decoration: const InputDecoration(
          labelText: 'Username',
          prefixIcon: Icon(Icons.person_outline),
          border: OutlineInputBorder(),
        ),
      ),
    ];

    if (mode == AuthMode.httpsUserPass) {
      fields.add(
        TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password or token',
            prefixIcon: Icon(Icons.password),
            border: OutlineInputBorder(),
          ),
        ),
      );
    }

    if (mode == AuthMode.sshKeyFiles) {
      fields.addAll([
        TextField(
          controller: publicKeyPathController,
          decoration: const InputDecoration(
            labelText: 'Public key path',
            prefixIcon: Icon(Icons.file_present_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        TextField(
          controller: privateKeyPathController,
          decoration: const InputDecoration(
            labelText: 'Private key path',
            prefixIcon: Icon(Icons.file_present),
            border: OutlineInputBorder(),
          ),
        ),
        TextField(
          controller: passphraseController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Passphrase',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
        ),
      ]);
    }

    if (mode == AuthMode.sshKeyMemory) {
      fields.addAll([
        TextField(
          controller: publicKeyController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Public key',
            prefixIcon: Icon(Icons.article_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        TextField(
          controller: privateKeyController,
          minLines: 3,
          maxLines: 6,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Private key',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
        ),
        TextField(
          controller: passphraseController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Passphrase',
            prefixIcon: Icon(Icons.password),
            border: OutlineInputBorder(),
          ),
        ),
      ]);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 760 ? 2 : 1;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final field in fields)
              SizedBox(
                width: columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 12) / 2,
                child: field,
              ),
          ],
        );
      },
    );
  }
}

class _PlatformsTab extends StatelessWidget {
  const _PlatformsTab({required this.diagnostics});

  final PlatformDiagnostics? diagnostics;

  @override
  Widget build(BuildContext context) {
    final notes = diagnostics?.notes ?? const <String>[];
    return _ScrollableTab(
      children: [
        _Section(
          title: 'Supported Platforms',
          icon: Icons.devices_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Android, iOS, Linux, macOS, and Windows. Web is not supported because git2dart uses FFI and libgit2.',
              ),
              const SizedBox(height: 12),
              for (final note in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(note)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LogTab extends StatelessWidget {
  const _LogTab({required this.store});

  final GitLogStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return _ScrollableTab(
          children: [
            _Section(
              title: 'Operation Log',
              icon: Icons.receipt_long_outlined,
              child: store.events.isEmpty
                  ? const Text('No operations yet.')
                  : Column(
                      children: [
                        for (final event in store.events) _LogRow(event: event),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SnapshotView extends StatelessWidget {
  const _SnapshotView({required this.snapshot});

  final GitWorkspaceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.repoPath.isEmpty) {
      return const Text(
        'Run Reset + seed to create the app-private repository.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KeyValue(label: 'Repository', value: snapshot.repoPath),
        _KeyValue(label: 'Bare remote', value: snapshot.bareRemotePath),
        _KeyValue(
          label: 'HEAD',
          value: '${snapshot.headName} ${snapshot.headSha}',
        ),
        _KeyValue(label: 'Branches', value: snapshot.branches.join(', ')),
        _KeyValue(label: 'Remotes', value: snapshot.remotes.join(', ')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final file in snapshot.files)
              Chip(
                avatar: const Icon(Icons.description_outlined, size: 18),
                label: Text(file),
              ),
          ],
        ),
      ],
    );
  }
}

class _StatusList extends StatelessWidget {
  const _StatusList({required this.entries});

  final List<StatusEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final entry in entries)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.change_circle_outlined),
            title: Text(entry.path),
            subtitle: Text(entry.statuses.join(', ')),
          ),
      ],
    );
  }
}

class _CommitList extends StatelessWidget {
  const _CommitList({required this.commits});

  final List<CommitSummary> commits;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final commit in commits)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.commit_outlined),
            title: Text(commit.summary),
            subtitle: Text(
              '${commit.sha.substring(0, 7)} · ${commit.author} <${commit.email}> · parents: ${commit.parentCount}',
            ),
          ),
      ],
    );
  }
}

class _RemoteRefsList extends StatelessWidget {
  const _RemoteRefsList({required this.refs});

  final List<RemoteRefSummary> refs;

  @override
  Widget build(BuildContext context) {
    if (refs.isEmpty) {
      return const Text('Remote did not return refs.');
    }
    return Column(
      children: [
        for (final ref in refs)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.label_outline),
            title: Text(ref.name),
            subtitle: Text(
              ref.symRef.isEmpty
                  ? ref.oid.substring(0, 12)
                  : '${ref.oid.substring(0, 12)} -> ${ref.symRef}',
            ),
          ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.event});

  final GitOperationEvent event;

  @override
  Widget build(BuildContext context) {
    final icon = switch (event.kind) {
      GitOperationEventKind.info => Icons.info_outline,
      GitOperationEventKind.progress => Icons.sync,
      GitOperationEventKind.error => Icons.error_outline,
    };
    final color = switch (event.kind) {
      GitOperationEventKind.info => Theme.of(context).colorScheme.primary,
      GitOperationEventKind.progress => Theme.of(context).colorScheme.tertiary,
      GitOperationEventKind.error => Theme.of(context).colorScheme.error,
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(event.message),
      subtitle: event.details.isEmpty
          ? Text(event.timestamp.toIso8601String())
          : Text('${event.details}\n${event.timestamp.toIso8601String()}'),
    );
  }
}

class _ScrollableTab extends StatelessWidget {
  const _ScrollableTab({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) => children[index],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _CommandButton extends StatelessWidget {
  const _CommandButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: wide ? 260 : 120,
        maxWidth: wide ? 520 : 220,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(value, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(child: SelectableText(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}

class _MonoBlock extends StatelessWidget {
  const _MonoBlock(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
    );
  }
}
