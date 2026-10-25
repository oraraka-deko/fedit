import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/git_models.dart';
import '../providers/source_control_manager.dart';
import '../utils/colors.dart';

class SourceControlPanel extends StatefulWidget {
  final SourceControlManager scm;
  final Directory projectRoot;
  final void Function(GitFileStatus fileStatus, {bool staged}) onOpenDiff;
  final void Function(File file)? onOpenFile;

  const SourceControlPanel({
    super.key,
    required this.scm,
    required this.projectRoot,
    required this.onOpenDiff,
    this.onOpenFile,
  });

  @override
  State<SourceControlPanel> createState() => _SourceControlPanelState();
}

class _SourceControlPanelState extends State<SourceControlPanel> {
  bool _changesExpanded = true;
  bool _stagedExpanded = true;
  bool _untrackedExpanded = true;
  bool _graphExpanded = true;
  bool _repoExpanded = true;

  @override
  Widget build(BuildContext context) {
    final scm = widget.scm;
    const bg = Color(0xFF1E1E1E);
    const border = Color(0xFF282828);

    return Container(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          _buildHeaderBar(scm),
          const Divider(height: 1, color: border),

          // Main Scrollable Area
          Expanded(
            child: scm.isBusy && !scm.isInitialized
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Repositories Row
                        _buildRepositoriesSection(scm),

                        // Commit Message Box & Action
                        _buildCommitBox(scm),

                        // Error Banner if any
                        if (scm.lastError != null) _buildErrorBanner(scm),

                        // Staged Changes Accordion
                        if (scm.stagedChanges.isNotEmpty)
                          _buildStagedChangesSection(scm),

                        // Changes Accordion (Working tree)
                        _buildChangesSection(scm),

                        // Untracked Changes Accordion
                        if (scm.untrackedChanges.isNotEmpty)
                          _buildUntrackedSection(scm),

                        const SizedBox(height: 8),

                        // Git Graph / History Accordion
                        _buildGraphSection(scm),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBar(SourceControlManager scm) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Text(
            'SOURCE CONTROL',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            color: Colors.white70,
            tooltip: 'Refresh',
            splashRadius: 16,
            onPressed: scm.isBusy ? null : scm.refresh,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, size: 16, color: Colors.white70),
            tooltip: 'More Actions',
            splashRadius: 16,
            color: const Color(0xFF252526),
            onSelected: (val) {
              if (val == 'stage_all') scm.stageAll();
              if (val == 'unstage_all') scm.unstageAll();
              if (val == 'discard_all') scm.discardAll();
              if (val == 'undo_commit') scm.undoCommit(soft: true);
              if (val == 'sync') scm.sync();
              if (val == 'pull') scm.pull();
              if (val == 'push') scm.push();
              if (val == 'fetch') scm.fetch();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'stage_all', child: Text('Stage All Changes', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'unstage_all', child: Text('Unstage All Changes', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'discard_all', child: Text('Discard All Changes', style: TextStyle(color: Colors.redAccent))),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'undo_commit', child: Text('Undo Last Commit', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'sync', child: Text('Sync Changes', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'pull', child: Text('Pull', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'push', child: Text('Push', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'fetch', child: Text('Fetch', style: TextStyle(color: Colors.white))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRepositoriesSection(SourceControlManager scm) {
    final repoName = p.basename(widget.projectRoot.path);
    final branch = scm.currentBranch ?? 'main';

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _repoExpanded = !_repoExpanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(
                  _repoExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  size: 16,
                  color: Colors.white70,
                ),
                const SizedBox(width: 4),
                const Text(
                  'REPOSITORIES',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_repoExpanded)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFF141414),
            child: Row(
              children: [
                const Icon(Icons.book_outlined, size: 15, color: Colors.white70),
                const SizedBox(width: 8),
                Text(
                  repoName,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                // Branch Pill (Clickable)
                InkWell(
                  onTap: () => _showBranchDialog(context),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.fork_right, size: 13, color: Color(0xFF58A6FF)),
                        const SizedBox(width: 4),
                        Text(
                          branch,
                          style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        if (scm.workingTreeChanges.isNotEmpty || scm.stagedChanges.isNotEmpty)
                          const Text('*', style: TextStyle(color: Colors.amberAccent, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Sync Button
                InkWell(
                  onTap: scm.isBusy ? null : scm.sync,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sync, size: 13, color: Colors.white70),
                        if (scm.behindCount > 0 || scm.aheadCount > 0) ...[
                          const SizedBox(width: 3),
                          Text(
                            '↓${scm.behindCount} ↑${scm.aheadCount}',
                            style: const TextStyle(color: Colors.white70, fontSize: 10),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Repo Menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, size: 15, color: Colors.white70),
                  tooltip: 'Repository Actions',
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  color: const Color(0xFF252526),
                  onSelected: (val) {
                    if (val == 'sync') scm.sync();
                    if (val == 'pull') scm.pull();
                    if (val == 'push') scm.push();
                    if (val == 'fetch') scm.fetch();
                    if (val == 'undo_commit') scm.undoCommit(soft: true);
                    if (val == 'branches') _showBranchDialog(context);
                    if (val == 'stashes') _showStashDialog(context);
                    if (val == 'rebase') _showRebaseDialog(context);
                    if (val == 'remotes') _showRemoteDialog(context);
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'sync',
                      child: Text(
                        'Sync Changes (${scm.behindCount}↓ ${scm.aheadCount}↑)',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const PopupMenuItem(value: 'pull', child: Text('Pull', style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(value: 'push', child: Text('Push', style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(value: 'fetch', child: Text('Fetch', style: TextStyle(color: Colors.white))),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'undo_commit', child: Text('Undo Last Commit', style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(value: 'branches', child: Text('Branches...', style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(value: 'stashes', child: Text('Stashes...', style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(value: 'rebase', child: Text('Rebase...', style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(value: 'remotes', child: Text('Remotes...', style: TextStyle(color: Colors.white))),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCommitBox(SourceControlManager scm) {
    final branch = scm.currentBranch ?? 'main';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Text area
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF252526),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF3C3C3C)),
            ),
            child: Stack(
              children: [
                TextField(
                  controller: scm.commitMessageController,
                  maxLines: 3,
                  minLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Message (Ctrl+Enter to commit on "$branch")',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.only(left: 10, right: 36, top: 10, bottom: 10),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton(
                    icon: const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF58A6FF)),
                    tooltip: 'Generate commit message from changes',
                    splashRadius: 14,
                    onPressed: () {
                      final changes = [...scm.stagedChanges, ...scm.workingTreeChanges];
                      if (changes.isNotEmpty) {
                        final files = changes.map((c) => p.basename(c.path)).take(3).join(', ');
                        scm.commitMessageController.text = 'Update $files';
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // VS Code-style Split Commit button
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0078D4),
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.horizontal(left: Radius.circular(5)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: scm.isBusy ? null : () => _performCommit(scm),
                    child: scm.isBusy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.check, size: 16),
                              SizedBox(width: 6),
                              Text('Commit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ],
                          ),
                  ),
                ),
              ),
              Container(
                height: 34,
                decoration: const BoxDecoration(
                  color: Color(0xFF0078D4),
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(5)),
                ),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.white),
                  tooltip: 'More Commit Options',
                  splashRadius: 14,
                  color: const Color(0xFF252526),
                  onSelected: (val) async {
                    final msg = scm.commitMessageController.text.trim();
                    if (val == 'commit') {
                      await _performCommit(scm);
                    } else if (val == 'commit_push') {
                      if (msg.isEmpty) {
                        _showMsg('Please enter a commit message');
                        return;
                      }
                      await scm.commitAndPush();
                    } else if (val == 'commit_sync') {
                      if (msg.isEmpty) {
                        _showMsg('Please enter a commit message');
                        return;
                      }
                      await scm.commitAndSync();
                    } else if (val == 'amend') {
                      if (msg.isEmpty) {
                        _showMsg('Please enter a commit message for amend');
                        return;
                      }
                      await scm.commitAmend();
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'commit', child: Text('Commit', style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(value: 'commit_push', child: Text('Commit & Push', style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(value: 'commit_sync', child: Text('Commit & Sync', style: TextStyle(color: Colors.white))),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'amend', child: Text('Commit (Amend)', style: TextStyle(color: Colors.white))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _performCommit(SourceControlManager scm) async {
    final msg = scm.commitMessageController.text.trim();
    if (msg.isEmpty) {
      _showMsg('Please enter a commit message');
      return;
    }
    await scm.commit(message: msg);
  }

  void _showMsg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  Widget _buildErrorBanner(SourceControlManager scm) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF5A1D1D),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.redAccent),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              scm.lastError ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStagedChangesSection(SourceControlManager scm) {
    final count = scm.stagedChanges.length;

    return Column(
      children: [
        _buildAccordionHeader(
          title: 'STAGED CHANGES',
          count: count,
          isExpanded: _stagedExpanded,
          onToggle: () => setState(() => _stagedExpanded = !_stagedExpanded),
          actions: [
            IconButton(
              icon: const Icon(Icons.remove, size: 16),
              color: Colors.white70,
              tooltip: 'Unstage All Changes',
              splashRadius: 14,
              onPressed: scm.isBusy ? null : scm.unstageAll,
            ),
          ],
        ),
        if (_stagedExpanded)
          ...scm.stagedChanges.map((fileStatus) => _buildFileRow(scm, fileStatus, staged: true)),
      ],
    );
  }

  Widget _buildChangesSection(SourceControlManager scm) {
    final count = scm.workingTreeChanges.length;

    return Column(
      children: [
        _buildAccordionHeader(
          title: 'CHANGES',
          count: count,
          isExpanded: _changesExpanded,
          onToggle: () => setState(() => _changesExpanded = !_changesExpanded),
          actions: [
            IconButton(
              icon: const Icon(Icons.undo, size: 15),
              color: Colors.white70,
              tooltip: 'Discard All Changes',
              splashRadius: 14,
              onPressed: scm.isBusy || count == 0 ? null : scm.discardAll,
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 16),
              color: Colors.white70,
              tooltip: 'Stage All Changes',
              splashRadius: 14,
              onPressed: scm.isBusy || count == 0 ? null : scm.stageAll,
            ),
          ],
        ),
        if (_changesExpanded)
          if (count == 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text('No changes detected in working tree', style: TextStyle(color: Colors.white38, fontSize: 12)),
            )
          else
            ...scm.workingTreeChanges.map((fileStatus) => _buildFileRow(scm, fileStatus, staged: false)),
      ],
    );
  }

  Widget _buildUntrackedSection(SourceControlManager scm) {
    final count = scm.untrackedChanges.length;

    return Column(
      children: [
        _buildAccordionHeader(
          title: 'UNTRACKED',
          count: count,
          isExpanded: _untrackedExpanded,
          onToggle: () => setState(() => _untrackedExpanded = !_untrackedExpanded),
          actions: [
            IconButton(
              icon: const Icon(Icons.add, size: 16),
              color: Colors.white70,
              tooltip: 'Track All Files',
              splashRadius: 14,
              onPressed: scm.isBusy ? null : scm.stageAll,
            ),
          ],
        ),
        if (_untrackedExpanded)
          ...scm.untrackedChanges.map((fileStatus) => _buildFileRow(scm, fileStatus, staged: false)),
      ],
    );
  }

  Widget _buildAccordionHeader({
    required String title,
    required int count,
    required bool isExpanded,
    required VoidCallback onToggle,
    List<Widget>? actions,
  }) {
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 6, right: 6),
      color: const Color(0xFF1E1E1E),
      child: Row(
        children: [
          InkWell(
            onTap: onToggle,
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  size: 16,
                  color: Colors.white70,
                ),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          ...?actions,
        ],
      ),
    );
  }

  Widget _buildFileRow(SourceControlManager scm, GitFileStatus fileStatus, {required bool staged}) {
    final fileName = p.basename(fileStatus.path);
    final parentDir = p.dirname(fileStatus.path);
    final statusColor = Color(fileStatus.statusColor);

    return InkWell(
      onTap: () => widget.onOpenDiff(fileStatus, staged: staged),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // File icon
            Icon(Icons.insert_drive_file_outlined, size: 14, color: AppColors.accent),
            const SizedBox(width: 8),

            // File Name
            Text(
              fileName,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 6),

            // Directory Subtitle
            Expanded(
              child: Text(
                parentDir == '.' ? '' : parentDir,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Action buttons on row
            if (staged)
              IconButton(
                icon: const Icon(Icons.remove, size: 14, color: Colors.white54),
                tooltip: 'Unstage Changes',
                splashRadius: 12,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () => scm.unstage(fileStatus.path),
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.undo, size: 13, color: Colors.white54),
                tooltip: 'Discard Changes',
                splashRadius: 12,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () => scm.discard(fileStatus.path),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 14, color: Colors.white54),
                tooltip: 'Stage Changes',
                splashRadius: 12,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () => scm.stage(fileStatus.path),
              ),
            ],

            const SizedBox(width: 4),

            // Status letter (M, A, D, U)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                fileStatus.statusLetter,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraphSection(SourceControlManager scm) {
    final commits = scm.recentCommits;

    return Column(
      children: [
        _buildAccordionHeader(
          title: 'GRAPH',
          count: commits.length,
          isExpanded: _graphExpanded,
          onToggle: () => setState(() => _graphExpanded = !_graphExpanded),
          actions: [
            // Auto layout tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text('Auto', style: TextStyle(color: Colors.white54, fontSize: 10)),
            ),
            // Target / Reveal HEAD
            IconButton(
              icon: const Icon(Icons.my_location, size: 14),
              color: Colors.white70,
              tooltip: 'Reveal Current Commit',
              splashRadius: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              onPressed: scm.refresh,
            ),
            // Pull
            IconButton(
              icon: const Icon(Icons.south, size: 13),
              color: Colors.white70,
              tooltip: 'Pull',
              splashRadius: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              onPressed: scm.isBusy ? null : scm.pull,
            ),
            // Push
            IconButton(
              icon: const Icon(Icons.north, size: 13),
              color: Colors.white70,
              tooltip: 'Push',
              splashRadius: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              onPressed: scm.isBusy ? null : scm.push,
            ),
            // Refresh
            IconButton(
              icon: const Icon(Icons.refresh, size: 14),
              color: Colors.white70,
              tooltip: 'Refresh Graph',
              splashRadius: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              onPressed: scm.isBusy ? null : scm.refresh,
            ),
          ],
        ),
        if (_graphExpanded)
          if (commits.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text('No commits yet', style: TextStyle(color: Colors.white38, fontSize: 12)),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: commits.length,
              itemBuilder: (context, index) {
                final commit = commits[index];
                final isLast = index == commits.length - 1;
                return _buildCommitRow(commit, isLast: isLast);
              },
            ),
      ],
    );
  }

  Widget _buildCommitRow(GitCommitSummary commit, {bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Visual Graph Column (Node and vertical connector)
          SizedBox(
            width: 16,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: commit.isHead ? 10 : 8,
                  height: commit.isHead ? 10 : 8,
                  decoration: BoxDecoration(
                    color: commit.isHead ? const Color(0xFF0078D4) : const Color(0xFF58A6FF),
                    shape: BoxShape.circle,
                    border: commit.isHead ? Border.all(color: Colors.white, width: 1.5) : null,
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 28,
                    color: const Color(0xFF388BFD).withValues(alpha: 0.4),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Message, Branch Pills & Author Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        commit.message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    // Branch Tags
                    for (final bName in commit.branchNames) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF005FB8).withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF388BFD), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.fork_right, size: 10, color: Color(0xFF58A6FF)),
                            const SizedBox(width: 2),
                            Text(
                              bName,
                              style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Remote Branch Tags (with cloud icon matching VS Code)
                    for (final rName in commit.remoteBranchNames) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5A2A82).withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFA371F7), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_outlined, size: 10, color: Color(0xFFD2A8FF)),
                            const SizedBox(width: 2),
                            Text(
                              rName,
                              style: const TextStyle(color: Color(0xFFD2A8FF), fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      commit.shortSha,
                      style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 10, fontFamily: 'monospace'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${commit.authorName} • ${_formatTimeAgo(commit.committedAt)}',
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  // ===========================================================================
  // Dialogs: Branches, Remotes, Stashes, Rebase
  // ===========================================================================

  void _showBranchDialog(BuildContext context) {
    final scm = widget.scm;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: Row(
          children: const [
            Icon(Icons.fork_right, color: Color(0xFF58A6FF), size: 20),
            SizedBox(width: 8),
            Text('Switch or Create Branch', style: TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Create Branch Button
              ListTile(
                leading: const Icon(Icons.add, color: Color(0xFF58A6FF), size: 18),
                title: const Text('Create New Branch...', style: TextStyle(color: Color(0xFF58A6FF), fontSize: 13, fontWeight: FontWeight.bold)),
                dense: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _showCreateBranchPrompt(context);
                },
              ),
              const Divider(color: Color(0xFF3C3C3C)),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 250),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: scm.branches.length,
                  itemBuilder: (c, idx) {
                    final b = scm.branches[idx];
                    final isCurrent = b.isCurrent;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isCurrent ? Icons.check : Icons.fork_right,
                        color: isCurrent ? const Color(0xFF58A6FF) : Colors.white54,
                        size: 16,
                      ),
                      title: Text(
                        b.name,
                        style: TextStyle(
                          color: isCurrent ? const Color(0xFF58A6FF) : Colors.white,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: b.upstreamBranch != null
                          ? Text('Tracking: ${b.upstreamBranch}', style: const TextStyle(color: Colors.white38, fontSize: 11))
                          : null,
                      onTap: () async {
                        Navigator.pop(ctx);
                        if (!isCurrent) {
                          await scm.switchBranch(b.name);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  void _showCreateBranchPrompt(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text('Create Branch', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Branch name (e.g. feature/new-ui)',
            hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0078D4)),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                await widget.scm.createBranch(name, checkout: true);
              }
            },
            child: const Text('Create & Switch', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRemoteDialog(BuildContext context) {
    final scm = widget.scm;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: Row(
          children: const [
            Icon(Icons.cloud_outlined, color: Color(0xFF58A6FF), size: 20),
            SizedBox(width: 8),
            Text('Remote Repositories', style: TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add, color: Color(0xFF58A6FF), size: 18),
                title: const Text('Add Remote...', style: TextStyle(color: Color(0xFF58A6FF), fontSize: 13, fontWeight: FontWeight.bold)),
                dense: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddRemotePrompt(context);
                },
              ),
              const Divider(color: Color(0xFF3C3C3C)),
              if (scm.remotes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No remotes configured', style: TextStyle(color: Colors.white38, fontSize: 12)),
                )
              else
                ...scm.remotes.map((r) => ListTile(
                      dense: true,
                      title: Text(r.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(r.fetchUrl, style: const TextStyle(color: Colors.white54, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 14, color: Colors.white70),
                            tooltip: 'Change URL',
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showEditRemotePrompt(context, r.name, r.fetchUrl);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 14, color: Colors.redAccent),
                            tooltip: 'Remove Remote',
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await scm.removeRemote(name: r.name);
                            },
                          ),
                        ],
                      ),
                    )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  void _showAddRemotePrompt(BuildContext context) {
    final nameCtrl = TextEditingController(text: 'origin');
    final urlCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text('Add Remote', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(labelText: 'Remote Name', labelStyle: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(labelText: 'Repository URL', labelStyle: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0078D4)),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (name.isNotEmpty && url.isNotEmpty) {
                Navigator.pop(ctx);
                await widget.scm.addRemote(name: name, url: url);
              }
            },
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditRemotePrompt(BuildContext context, String name, String currentUrl) {
    final urlCtrl = TextEditingController(text: currentUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: Text('Edit Remote URL ($name)', style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: urlCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(labelText: 'New URL', labelStyle: TextStyle(color: Colors.white70)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0078D4)),
            onPressed: () async {
              final url = urlCtrl.text.trim();
              if (url.isNotEmpty) {
                Navigator.pop(ctx);
                await widget.scm.setRemoteUrl(name: name, url: url);
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showStashDialog(BuildContext context) {
    final scm = widget.scm;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: Row(
          children: const [
            Icon(Icons.archive_outlined, color: Color(0xFF58A6FF), size: 20),
            SizedBox(width: 8),
            Text('Stashes', style: TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add, color: Color(0xFF58A6FF), size: 18),
                title: const Text('Stash Current Changes...', style: TextStyle(color: Color(0xFF58A6FF), fontSize: 13, fontWeight: FontWeight.bold)),
                dense: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _showSaveStashPrompt(context);
                },
              ),
              const Divider(color: Color(0xFF3C3C3C)),
              if (scm.stashes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No saved stashes', style: TextStyle(color: Colors.white38, fontSize: 12)),
                )
              else
                ...scm.stashes.map((s) => ListTile(
                      dense: true,
                      title: Text(s.message.isEmpty ? 'stash@{${s.index}}' : s.message, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      subtitle: Text(s.sha.substring(0, 7), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.unarchive, size: 14, color: Colors.white70),
                            tooltip: 'Pop Stash',
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await scm.popStash(s.index);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 14, color: Colors.redAccent),
                            tooltip: 'Drop Stash',
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await scm.dropStash(s.index);
                            },
                          ),
                        ],
                      ),
                    )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  void _showSaveStashPrompt(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text('Stash Changes', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Optional stash message',
            hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0078D4)),
            onPressed: () async {
              final msg = controller.text.trim();
              Navigator.pop(ctx);
              await widget.scm.saveStash(message: msg.isNotEmpty ? msg : null);
            },
            child: const Text('Save Stash', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRebaseDialog(BuildContext context) {
    final scm = widget.scm;
    final otherBranches = scm.branches.where((b) => !b.isCurrent).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: Row(
          children: const [
            Icon(Icons.call_split, color: Color(0xFF58A6FF), size: 20),
            SizedBox(width: 8),
            Text('Rebase Current Branch Onto...', style: TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: otherBranches.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No other branches to rebase onto', style: TextStyle(color: Colors.white38, fontSize: 12)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: otherBranches.length,
                  itemBuilder: (c, idx) {
                    final b = otherBranches[idx];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.fork_right, color: Color(0xFF58A6FF), size: 16),
                      title: Text(b.name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await scm.rebase(upstreamBranch: b.name);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
