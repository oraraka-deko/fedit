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
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'stage_all', child: Text('Stage All Changes', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'unstage_all', child: Text('Unstage All Changes', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'discard_all', child: Text('Discard All Changes', style: TextStyle(color: Colors.redAccent))),
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
                Container(
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

          // Commit button
          SizedBox(
            height: 34,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0078D4),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: scm.isBusy
                  ? null
                  : () async {
                      final msg = scm.commitMessageController.text.trim();
                      if (msg.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a commit message')),
                        );
                        return;
                      }
                      await scm.commit(message: msg);
                    },
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
        ],
      ),
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
        ),
        if (_graphExpanded)
          if (commits.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text('No commits yet', style: TextStyle(color: Colors.white38, fontSize: 12)),
            )
          else
            ...commits.map((c) => _buildCommitRow(c)),
      ],
    );
  }

  Widget _buildCommitRow(GitCommitSummary commit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Commit Node
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF58A6FF),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),

          // Message & Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  commit.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
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
}
