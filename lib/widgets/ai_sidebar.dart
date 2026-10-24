import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

import '../ai/chat_service.dart';
import '../ai/config.dart';
import '../ai/models.dart';

class AiSidebar extends StatefulWidget {
  final ChatService chatService;
  const AiSidebar({super.key, required this.chatService});

  @override
  State<AiSidebar> createState() => _AiSidebarState();
}

class _AiSidebarState extends State<AiSidebar> with TickerProviderStateMixin {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _isHoveringSend = false;

  @override
  void initState() {
    super.initState();
    widget.chatService.addListener(_scrollToBottom);
  }

  @override
  void dispose() {
    widget.chatService.removeListener(_scrollToBottom);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _jumpToTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    widget.chatService.sendMessage(text);
  }

  Future<void> _showRenameThreadDialog() async {
    final active = widget.chatService.threads
        .where((thread) => thread.id == widget.chatService.activeThreadId)
        .toList();
    if (active.isEmpty) return;
    final controller = TextEditingController(text: active.first.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Rename thread'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (title == null || title.isEmpty) return;
    await widget.chatService.renameThread(widget.chatService.activeThreadId, title);
  }

  Future<void> _copyText(String text, {String message = 'Copied'}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E2227),
        border: Border(left: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.chatService,
              builder: (ctx, _) {
                if (!widget.chatService.isInitialized) {
                  return const Center(child: CircularProgressIndicator());
                }

                final msgs = widget.chatService.visibleMessages;
                final phase = widget.chatService.streamPhase;
                final streamingText = widget.chatService.currentStreamingContent;
                final showStreaming =
                    phase == StreamPhase.streaming && streamingText.isNotEmpty;
                final showThinking = (phase == StreamPhase.thinking ||
                        phase == StreamPhase.executingTools) &&
                    !showStreaming;

                var itemCount = msgs.length;
                if (showStreaming) itemCount++;
                if (showThinking) itemCount++;

                return Stack(
                  children: [
                    ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 86),
                      itemCount: itemCount,
                      itemBuilder: (context, index) {
                        if (index < msgs.length) {
                          return _buildMsgBubble(msgs[index]);
                        }

                        if (showStreaming && index == msgs.length) {
                          return _buildMsgBubble(
                            Message(role: 'assistant', content: streamingText),
                            isStreaming: true,
                          );
                        }

                        return _buildThinkingIndicator();
                      },
                    ),
                    if (itemCount > 6)
                      Positioned(
                        right: 10,
                        bottom: 14,
                        child: _buildQuickScrollButtons(),
                      ),
                  ],
                );
              },
            ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF21252B),
        border: Border(bottom: BorderSide(color: Colors.black45)),
      ),
      child: ListenableBuilder(
        listenable: widget.chatService,
        builder: (context, _) {
          final threads = widget.chatService.threads;
          final active = threads
              .where((thread) => thread.id == widget.chatService.activeThreadId)
              .toList();
          final activeThreadId = active.isNotEmpty ? active.first.id : null;

          final models = widget.chatService.availableModels;
          final selectedModel = widget.chatService.currentModel;
          final hasSelectedModel = models.contains(selectedModel);
          final dropdownModels = hasSelectedModel
              ? models
              : (selectedModel.isEmpty ? models : [selectedModel, ...models]);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.blueAccent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'AI Assistant',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  _buildHeaderBtn(Icons.add_comment_outlined, () {
                    widget.chatService.createThread();
                  }),
                  PopupMenuButton<String>(
                    tooltip: 'Thread actions',
                    icon: const Icon(Icons.more_vert, color: Colors.grey),
                    onSelected: (value) async {
                      if (value == 'rename') {
                        await _showRenameThreadDialog();
                      } else if (value == 'delete') {
                        await widget.chatService
                            .deleteThread(widget.chatService.activeThreadId);
                      } else if (value == 'clear') {
                        await widget.chatService.clearActiveThread();
                      } else if (value == 'settings') {
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ConfigEditor()),
                        );
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename thread')),
                      PopupMenuItem(value: 'delete', child: Text('Delete thread')),
                      PopupMenuItem(value: 'clear', child: Text('Clear messages')),
                      PopupMenuItem(value: 'settings', child: Text('Settings')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: activeThreadId,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Thread',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      items: threads
                          .map(
                            (thread) => DropdownMenuItem<String>(
                              value: thread.id,
                              child: Text(
                                thread.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (id) {
                        if (id == null) return;
                        widget.chatService.switchThread(id);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedModel.isEmpty
                          ? (dropdownModels.isEmpty ? null : dropdownModels.first)
                          : selectedModel,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Model',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      items: dropdownModels
                          .map(
                            (model) => DropdownMenuItem<String>(
                              value: model,
                              child: Text(model, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        widget.chatService.setCurrentModel(value);
                      },
                    ),
                  ),
                  IconButton(
                    onPressed: widget.chatService.isFetchingModels
                        ? null
                        : widget.chatService.refreshAvailableModels,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                ],
              ),
              if (widget.chatService.modelFetchError != null)
                Text(
                  widget.chatService.modelFetchError!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.orange, fontSize: 11),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF21252B),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2C313C),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Ask me anything...',
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringSend = true),
            onExit: (_) => setState(() => _isHoveringSend = false),
            child: GestureDetector(
              onTap: _submit,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isHoveringSend
                      ? Colors.blueAccent
                      : Colors.blueAccent.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBtn(IconData icon, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: Colors.grey, size: 20),
      splashRadius: 20,
      onPressed: onTap,
    );
  }

  Widget _buildQuickScrollButtons() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xCC161A20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildQuickScrollButton(
            icon: Icons.keyboard_double_arrow_up_rounded,
            tooltip: 'Jump to first message',
            onTap: _jumpToTop,
          ),
          const Divider(height: 1, color: Colors.white10),
          _buildQuickScrollButton(
            icon: Icons.keyboard_double_arrow_down_rounded,
            tooltip: 'Jump to latest message',
            onTap: _jumpToBottom,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickScrollButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 18, color: Colors.white70),
          ),
        ),
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 14,
            backgroundColor: Color(0xFF353B45),
            child: Icon(Icons.psychology, size: 16, color: Colors.blueAccent),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF2C313C),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: const _JumpingDots(),
          ),
        ],
      ),
    );
  }

  Widget _buildMsgBubble(Message msg, {bool isStreaming = false}) {
    final isUser = msg.role == 'user';
    final isTool = msg.role == 'tool';
    final isAssistant = msg.role == 'assistant';

    if (isTool) {
      return _ToolOutputCard(content: msg.content);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              radius: 14,
              backgroundColor: Color(0xFF353B45),
              child: Icon(Icons.auto_awesome, size: 16, color: Colors.blueAccent),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                decoration: BoxDecoration(
                  color: isUser ? const Color(0xFF2457E6) : const Color(0xFF262C36),
                  gradient: isUser
                      ? const LinearGradient(
                          colors: [Color(0xFF2864FF), Color(0xFF4583FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  border: Border.all(
                    color: isUser ? Colors.white24 : Colors.white10,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(isUser ? 16 : 6),
                    topRight: Radius.circular(isUser ? 6 : 16),
                    bottomLeft: const Radius.circular(16),
                    bottomRight: const Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.24),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isUser ? 'You' : 'Agent',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (msg.toolCalls != null && msg.toolCalls!.isNotEmpty)
                      ...msg.toolCalls!.map(
                        (tc) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.code,
                                size: 12,
                                color: Colors.yellowAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Function: ${tc.function.name}',
                                style: const TextStyle(
                                  color: Colors.yellowAccent,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (isAssistant)
                      _AssistantMarkdown(
                        content: msg.content,
                        isStreaming: isStreaming,
                        onCopy: _copyText,
                      )
                    else
                      SelectableText(
                        msg.content,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14.2,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 14,
              backgroundColor: Color(0xFF353B45),
              child: Icon(Icons.person, size: 16, color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssistantMarkdown extends StatelessWidget {
  final String content;
  final bool isStreaming;
  final Future<void> Function(String text, {String message}) onCopy;

  const _AssistantMarkdown({
    required this.content,
    required this.isStreaming,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              iconSize: 16,
              tooltip: 'Copy message',
              visualDensity: VisualDensity.compact,
              onPressed: content.trim().isEmpty
                  ? null
                  : () => onCopy(content, message: 'Message copied'),
              icon: const Icon(Icons.copy, color: Colors.white70),
            ),
          ],
        ),
        MarkdownBody(
          data: content,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14.4,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
            h1: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
            h2: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
            ),
            h3: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 15.2,
              fontWeight: FontWeight.w700,
            ),
            listBullet: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14.2,
              fontWeight: FontWeight.w500,
            ),
            strong: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14.4,
              fontWeight: FontWeight.w700,
              height: 1.55,
            ),
            code: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
            blockquote: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 13.8,
              fontWeight: FontWeight.w500,
            ),
          ),
          builders: {
            'pre': _CodeBlockBuilder(onCopy: onCopy),
          },
        ),
        if (isStreaming)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'typing...',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
      ],
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  final Future<void> Function(String text, {String message}) onCopy;
  _CodeBlockBuilder({required this.onCopy});

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final raw = element.textContent.replaceAll('\r\n', '\n');
    return _CodeBlockWidget(code: raw, onCopy: onCopy);
  }
}

class _CodeBlockWidget extends StatelessWidget {
  final String code;
  final Future<void> Function(String text, {String message}) onCopy;
  const _CodeBlockWidget({required this.code, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final lines = code.split('\n');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF181A1F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.code, size: 14, color: Colors.white70),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Code Block',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
                IconButton(
                  iconSize: 14,
                  tooltip: 'Copy block',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onCopy(code, message: 'Code block copied'),
                  icon: const Icon(Icons.copy, color: Colors.white70),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(lines.length, (index) {
                final line = lines[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${index + 1}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        line,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
                    IconButton(
                      iconSize: 13,
                      tooltip: 'Copy line',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onCopy(line, message: 'Line copied'),
                      icon: const Icon(Icons.content_copy, color: Colors.white54),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolOutputCard extends StatefulWidget {
  final String content;
  const _ToolOutputCard({required this.content});

  @override
  State<_ToolOutputCard> createState() => _ToolOutputCardState();
}

class _ToolOutputCardState extends State<_ToolOutputCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final lines = '\n'.allMatches(widget.content).length + 1;
    final charCount = widget.content.length;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF181A1F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    color: Colors.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.build_circle_outlined, color: Colors.orange, size: 14),
                  const SizedBox(width: 6),
                  const Text(
                    'TOOL OUTPUT',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$lines lines • $charCount chars',
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText(
                widget.content,
                style: const TextStyle(
                  color: Colors.grey,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _JumpingDots extends StatefulWidget {
  const _JumpingDots();
  @override
  State<_JumpingDots> createState() => _JumpingDotsState();
}

class _JumpingDotsState extends State<_JumpingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return ScaleTransition(
          scale: DelayTween(begin: 0.0, end: 1.0, delay: index * 0.2).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.blueAccent,
              shape: BoxShape.circle,
            ),
          ),
        );
      }),
    );
  }
}

class DelayTween extends Tween<double> {
  final double delay;
  DelayTween({super.begin, super.end, required this.delay});

  @override
  double lerp(double t) {
    return super.lerp((math.sin((t - delay) * 2 * math.pi) + 1) / 2);
  }
}
