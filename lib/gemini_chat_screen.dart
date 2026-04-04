import 'dart:async';

import 'package:cross_cache/cross_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart'
    hide InMemoryChatController;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flyer_chat_image_message/flyer_chat_image_message.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:flyer_chat_text_stream_message/flyer_chat_text_stream_message.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'gemini_stream_manager.dart';
import 'in_memory_chat_controller.dart';

const Duration _kChunkAnimationDuration = Duration(milliseconds: 350);

class GeminiChatScreen extends StatefulWidget {
  final String geminiApiKey;

  const GeminiChatScreen({super.key, required this.geminiApiKey});

  @override
  State<GeminiChatScreen> createState() => _GeminiChatScreenState();
}

class _GeminiChatScreenState extends State<GeminiChatScreen> {
  final _uuid = const Uuid();
  final _crossCache = CrossCache();
  final _scrollController = ScrollController();
  final _chatController = InMemoryChatController();

  final _currentUser = const User(id: 'me');
  final _agent = const User(id: 'agent');

  late final GenerativeModel _model;
  late ChatSession _chatSession;
  late final GeminiStreamManager _streamManager;

  bool _isStreaming = false;

  // ── Scroll state ──────────────────────────────────────────────────────────
  bool _isAtBottom = true;
  bool _isProgrammaticScroll = false;
  bool _userIsDragging = false; // ✅ المستخدم بيسكرول بإيده فعلاً
  Timer? _autoScrollTimer; // ✅ الحل الأساسي

  StreamSubscription? _currentStreamSubscription;
  String? _currentStreamId;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);

    _streamManager = GeminiStreamManager(
      chatController: _chatController,
      chunkAnimationDuration: _kChunkAnimationDuration,
    );

    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: widget.geminiApiKey,
      safetySettings: [
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.none),
      ],
    );

    _chatSession = _model.startChat();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _currentStreamSubscription?.cancel();
    _streamManager.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    _crossCache.dispose();
    super.dispose();
  }

  // ── Scroll Logic ──────────────────────────────────────────────────────────

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    // لو السكرول برمجي — تجاهل
    if (_isProgrammaticScroll) return;

    final position = _scrollController.position;
    _isAtBottom = (position.maxScrollExtent - position.pixels) < 80;
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    if (!_isAtBottom) return;

    // ✅ jumpTo بدل animateTo — synchronous فوراً
    // animateTo كانت المشكلة: أثناء الـ animation بييجي content جديد
    // فـ maxScrollExtent بيكبر والـ animation بتخلص عند القيمة القديمة
    // فـ _isAtBottom بيبقى false والـ timer بيوقف
    if (_userIsDragging) return; // ✅ متتغلبش على الـ drag اليدوي
    _isProgrammaticScroll = true;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    _isProgrammaticScroll = false;
  }

  /// ✅ بيشتغل كل 100ms طول الـ streaming
  /// بيضمن إن الـ scroll دايماً up-to-date مع الـ layout الجديد
  void _startAutoScrollTimer() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        // ✅ addPostFrameCallback عشان Flutter web يكون خلّص الـ layout
        // قبل ما نقرأ maxScrollExtent ونعمل jumpTo
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      },
    );
  }

  void _stopAutoScrollTimer() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    // scroll أخير عشان نتأكد إن آخر chunk اتشاف
    _scrollToBottom();
  }

  // ── Stream Control ────────────────────────────────────────────────────────

  void _stopCurrentStream() {
    if (_currentStreamSubscription != null && _currentStreamId != null) {
      _currentStreamSubscription!.cancel();
      _currentStreamSubscription = null;
      _stopAutoScrollTimer();

      setState(() => _isStreaming = false);

      if (_currentStreamId != null) {
        _streamManager.errorStream(_currentStreamId!, 'Stream stopped by user');
        _currentStreamId = null;
      }
    }
  }

  void _handleStreamError(
    String streamId,
    dynamic error,
    TextStreamMessage? streamMessage,
  ) async {
    if (mounted) _stopAutoScrollTimer(); // ✅ check mounted أولاً
    if (streamMessage != null) {
      await _streamManager.errorStream(streamId, error);
    }
    if (mounted) setState(() => _isStreaming = false);
    _currentStreamSubscription = null;
    _currentStreamId = null;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Gemini Chat')),
      body: Column(
        children: [
          // ✅ الـ Chat list يملا باقي المساحة
          Expanded(
            child: ChangeNotifierProvider.value(
              value: _streamManager,
              child: Chat(
                builders: Builders(
                  chatAnimatedListBuilder: (context, itemBuilder) {
                    return NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollStartNotification &&
                            notification.dragDetails != null) {
                          _userIsDragging = true;
                        } else if (notification is ScrollEndNotification) {
                          _userIsDragging = false;
                          _handleScroll();
                        }
                        return false;
                      },
                      child: ChatAnimatedList(
                        scrollController: _scrollController,
                        itemBuilder: itemBuilder,
                      ),
                    );
                  },
                  imageMessageBuilder: (
                    context,
                    message,
                    index, {
                    required bool isSentByMe,
                    MessageGroupStatus? groupStatus,
                  }) =>
                      FlyerChatImageMessage(
                    message: message,
                    index: index,
                    showTime: false,
                    showStatus: false,
                  ),
                  // ✅ composer فاضي — هنحطه خارج الـ Chat
                  composerBuilder: (context) => const SizedBox.shrink(),
                  textMessageBuilder: (
                    context,
                    message,
                    index, {
                    required bool isSentByMe,
                    MessageGroupStatus? groupStatus,
                  }) =>
                      FlyerChatTextMessage(
                    message: message,
                    index: index,
                    showTime: false,
                    showStatus: false,
                    receivedBackgroundColor: Colors.transparent,
                    padding: message.authorId == _agent.id
                        ? EdgeInsets.zero
                        : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  textStreamMessageBuilder: (
                    context,
                    message,
                    index, {
                    required bool isSentByMe,
                    MessageGroupStatus? groupStatus,
                  }) {
                    final streamState = context
                        .watch<GeminiStreamManager>()
                        .getState(message.streamId);
                    return FlyerChatTextStreamMessage(
                      message: message,
                      index: index,
                      streamState: streamState,
                      chunkAnimationDuration: _kChunkAnimationDuration,
                      showTime: false,
                      showStatus: false,
                      receivedBackgroundColor: Colors.transparent,
                      padding: message.authorId == _agent.id
                          ? EdgeInsets.zero
                          : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    );
                  },
                ),
                chatController: _chatController,
                crossCache: _crossCache,
                currentUserId: _currentUser.id,
                onAttachmentTap: _handleAttachmentTap,
                resolveUser: (id) => Future.value(
                  switch (id) {
                    'me' => _currentUser,
                    'agent' => _agent,
                    _ => null,
                  },
                ),
                theme: ChatTheme.fromThemeData(theme),
              ),
            ),
          ),
          // ✅ الـ Composer في الأسفل دايماً خارج الـ Chat widget
          _Composer(
            isStreaming: _isStreaming,
            onStop: _stopCurrentStream,
            onSend: _handleMessageSend,
          ),
        ],
      ),
    );
  }

  // ── Message Handlers ──────────────────────────────────────────────────────

  void _handleMessageSend(String text) async {
    await _chatController.insertMessage(
      TextMessage(
        id: _uuid.v4(),
        authorId: _currentUser.id,
        createdAt: DateTime.now().toUtc(),
        text: text,
      ),
    );
    _sendContent(Content.text(text));
  }

  void _handleAttachmentTap() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    await _crossCache.downloadAndSave(image.path);
    await _chatController.insertMessage(
      ImageMessage(
        id: _uuid.v4(),
        authorId: _currentUser.id,
        createdAt: DateTime.now().toUtc(),
        source: image.path,
      ),
    );

    final bytes = await _crossCache.get(image.path);
    _sendContent(Content.data('image/jpeg', bytes));
  }

  void _sendContent(Content content) async {
    final streamId = _uuid.v4();
    _currentStreamId = streamId;
    TextStreamMessage? streamMessage;
    var messageInserted = false;

    setState(() => _isStreaming = true);

    // ✅ ابدأ الـ timer فوراً مع بداية الـ streaming
    _startAutoScrollTimer();

    Future<void> createAndInsertMessage() async {
      if (messageInserted || !mounted) return;
      messageInserted = true;

      streamMessage = TextStreamMessage(
        id: streamId,
        authorId: _agent.id,
        createdAt: DateTime.now().toUtc(),
        streamId: streamId,
      );

      await _chatController.insertMessage(streamMessage!);
      _streamManager.startStream(streamId, streamMessage!);
    }

    try {
      final response = _chatSession.sendMessageStream(content);

      _currentStreamSubscription = response.listen(
        (chunk) async {
          if (chunk.text != null) {
            final textChunk = chunk.text!;
            if (textChunk.isEmpty) return;

            if (!messageInserted) await createAndInsertMessage();
            if (streamMessage == null) return;

            _streamManager.addChunk(streamId, textChunk);
            // ✅ الـ Timer بيتولى الـ scroll تلقائياً كل 100ms
            // مش محتاج addPostFrameCallback هنا خالص
          }
        },
        onDone: () async {
          if (streamMessage != null) {
            await _streamManager.completeStream(streamId);
          }
          if (mounted) {
            _stopAutoScrollTimer(); // ✅ check mounted أولاً قبل لمس الـ scrollController
            setState(() => _isStreaming = false);
          }
          _currentStreamSubscription = null;
          _currentStreamId = null;
        },
        onError: (error) {
          _handleStreamError(streamId, error, streamMessage);
        },
      );
    } catch (error) {
      _handleStreamError(streamId, error, streamMessage);
    }
  }
}

// ── Composer Widget ───────────────────────────────────────────────────────────

class _Composer extends StatefulWidget {
  final bool isStreaming;
  final VoidCallback onStop;
  final Function(String) onSend;

  const _Composer({
    required this.isStreaming,
    required this.onStop,
    required this.onSend,
  });

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant, width: 1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _handleSend(),
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            if (widget.isStreaming)
              IconButton.filled(
                icon: const Icon(Icons.stop_rounded),
                onPressed: widget.onStop,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red.shade400,
                  foregroundColor: Colors.white,
                ),
              )
            else
              IconButton.filled(
                icon: const Icon(Icons.send_rounded),
                onPressed: _handleSend,
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
