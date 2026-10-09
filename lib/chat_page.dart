import 'package:flutter/material.dart';
import 'package:mobile_apps/app_config.dart';
import 'package:mobile_apps/sally_api.dart';
import 'package:mobile_apps/widgets/sally_logo.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatMessage {
  _ChatMessage({required this.text, required this.isUser});
  final String text;
  final bool   isUser;
}

class _ChatPageState extends State<ChatPage> {
  static const Color kBlue      = Color(0xFF1A335D);
  static const Color kUserBubble  = Color(0xFF1A335D);
  static const Color kSallyBubble = Color(0xFFE8EEF8);

  final SallyApiClient       _api            = SallyApiClient();
  final TextEditingController _inputCtrl      = TextEditingController();
  final ScrollController      _scrollCtrl     = ScrollController();

  final List<_ChatMessage> _messages = [];
  bool _isAsking = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = _inputCtrl.text.trim();
    if (question.isEmpty || _isAsking) return;

    setState(() {
      _messages.add(_ChatMessage(text: question, isUser: true));
      _isAsking = true;
    });
    _inputCtrl.clear();
    _scrollToBottom();

    final history = _messages
        .take(_messages.length - 1)
        .map((m) => <String, String>{
              'role': m.isUser ? 'user' : 'assistant',
              'content': m.text,
            })
        .toList();

    try {
      final answer = await _api.askPatient(question: question, history: history);
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(text: answer, isUser: false));
        _isAsking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(text: 'Sorry, I could not connect. Please try again.', isUser: false));
        _isAsking = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: kBlue,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            const SallyLogo(width: 36, height: 36),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Ask Sally', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('Ask me about your day', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: !isSallyApiConfigured && !kDemoMode
          ? _buildNotConfigured()
          : Column(
              children: [
                Expanded(child: _buildMessages()),
                _buildInputBar(),
              ],
            ),
    );
  }

  Widget _buildNotConfigured() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.signal_wifi_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Sally is not connected.',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A335D)),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Check the server connection in Settings.',
              style: TextStyle(fontSize: 16, color: Colors.black54, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SallyLogo(width: 72, height: 72),
              const SizedBox(height: 20),
              const Text(
                'Hi! I\'m Sally.',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A335D)),
              ),
              const SizedBox(height: 10),
              Text(
                'Ask me anything about your day,\nwhat you talked about or what you planned.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, color: Colors.grey.shade600, height: 1.5),
              ),
              const SizedBox(height: 28),
              ..._suggestions.map((s) => _SuggestionChip(text: s, onTap: () {
                _inputCtrl.text = s;
                _send();
              })),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length + (_isAsking ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _messages.length) return _buildTyping();
        return _buildBubble(_messages[i]);
      },
    );
  }

  Widget _buildBubble(_ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!msg.isUser) ...[
            const SallyLogo(width: 32, height: 32),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: msg.isUser ? kUserBubble : kSallyBubble,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(20),
                  topRight:    const Radius.circular(20),
                  bottomLeft:  Radius.circular(msg.isUser ? 20 : 4),
                  bottomRight: Radius.circular(msg.isUser ? 4  : 20),
                ),
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  fontSize: 17,
                  height: 1.5,
                  color: msg.isUser ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
          if (msg.isUser) const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _buildTyping() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SallyLogo(width: 32, height: 32),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              color: kSallyBubble,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: const SizedBox(width: 44, height: 14, child: _TypingDots()),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 14,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              style: const TextStyle(fontSize: 17),
              decoration: InputDecoration(
                hintText: 'Type your question here...',
                hintStyle: const TextStyle(fontSize: 16, color: Colors.black38),
                filled: true,
                fillColor: const Color(0xFFF4F7FF),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: BorderSide.none,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              minLines: 1,
              maxLines: 4,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _isAsking ? null : _send,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _isAsking ? Colors.grey.shade300 : kBlue,
                shape: BoxShape.circle,
              ),
              child: _isAsking
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }

  static const List<String> _suggestions = [
    'What did I talk about today?',
    'What did I plan to do this week?',
    'What did I say about my next appointment?',
  ];
}

// ── suggestion chip ───────────────────────────────────────────────────────────

class _SuggestionChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _SuggestionChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFE8EEF8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1A335D).withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.chat_bubble_outline, color: Color(0xFF1A335D), size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 16, color: Color(0xFF1A335D)))),
            const Icon(Icons.arrow_forward_ios, color: Color(0xFF1A335D), size: 14),
          ],
        ),
      ),
    );
  }
}

// ── animated typing dots ──────────────────────────────────────────────────────

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(3, (i) {
          final offset  = ((_ctrl.value * 3) - i).clamp(0.0, 1.0);
          final opacity = ((offset < 0.5 ? offset : 1.0 - offset) * 2).clamp(0.2, 1.0);
          return Opacity(
            opacity: opacity,
            child: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: Color(0xFF1A335D),
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
      ),
    );
  }
}
