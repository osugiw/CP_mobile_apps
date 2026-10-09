import 'package:flutter/material.dart';

import 'models/conversation.dart';
import 'models/stress_reading.dart';
import 'recommendation_page.dart';
import 'widgets/sally_logo.dart';
import 'widgets/stress_strip.dart';

/// List of recorded conversations, newest first, grouped by day.
///
/// Each card answers three quick questions: when was it, how did I sound,
/// and what was it about. The full transcript stays one tap away.
class ConversationsPage extends StatefulWidget {
  final ConversationRepository repository;

  const ConversationsPage({super.key, this.repository = const ConversationRepository()});

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  static const Color kBlue = Color(0xFF1A335D);

  late Future<List<Conversation>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchRecent();
  }

  Future<void> _reload() async {
    final f = widget.repository.fetchRecent();
    setState(() => _future = f);
    await f;
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
                  Text('Conversations',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('How you sounded, moment by moment',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white, size: 28),
              onPressed: _reload,
              tooltip: 'Refresh',
            ),
          ],
        ),
      ),
      body: FutureBuilder<List<Conversation>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: kBlue));
          }
          final items = snap.data ?? const <Conversation>[];
          if (snap.hasError || items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No conversations yet.\nThey will show up here after SALLY records one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: Colors.black54, height: 1.5),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            color: kBlue,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: _buildGrouped(items),
            ),
          );
        },
      ),
    );
  }

  /// Inserts a day header ("Today", "Yesterday", "Monday, Oct 6") before
  /// the first card of each day.
  List<Widget> _buildGrouped(List<Conversation> items) {
    final widgets = <Widget>[];
    String? lastDay;
    for (final c in items) {
      final day = _dayLabel(c.startedAt);
      if (day != lastDay) {
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
          child: Text(day,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kBlue)),
        ));
        lastDay = day;
      }
      widgets.add(_ConversationCard(conversation: c));
      widgets.add(const SizedBox(height: 14));
    }
    return widgets;
  }

  String _dayLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(t.year, t.month, t.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[t.weekday - 1]}, ${months[t.month - 1]} ${t.day}';
  }
}

// ── conversation card ─────────────────────────────────────────────────────────

class _ConversationCard extends StatefulWidget {
  final Conversation conversation;
  const _ConversationCard({required this.conversation});

  @override
  State<_ConversationCard> createState() => _ConversationCardState();
}

class _ConversationCardState extends State<_ConversationCard> {
  static const Color kBlue = Color(0xFF1A335D);
  static const Color kCardBlue = Color(0xFFF0F4FF);

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    final lvl = c.level;

    return Container(
      decoration: BoxDecoration(
        color: kCardBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBlue.withValues(alpha: 0.15), width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // When + how she sounded
          Row(
            children: [
              const Icon(Icons.access_time, size: 18, color: Colors.black45),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${formatClock(context, c.startedAt)} · ${c.durationMinutes} min',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                ),
              ),
              _MoodChip(level: lvl),
            ],
          ),
          const SizedBox(height: 10),

          // What it was about
          Text(
            c.summary,
            style: const TextStyle(fontSize: 17, height: 1.4, color: Colors.black87),
          ),
          const SizedBox(height: 12),

          // How stress moved during the talk
          StressStrip(values: c.stressCurve),
          const SizedBox(height: 4),
          const Text('Stress during this conversation',
              style: TextStyle(fontSize: 12, color: Colors.black45)),

          // Transcript, hidden until she asks for it
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _transcript(c),
          ),
          const SizedBox(height: 8),

          // Actions
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: kBlue),
                label: Text(
                  _expanded ? 'Hide transcript' : 'Read transcript',
                  style: const TextStyle(fontSize: 15, color: kBlue, fontWeight: FontWeight.w600),
                ),
              ),
              if (lvl != StressLevel.calm)
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RecommendationPage(
                        initialLevel: lvl,
                        detectedAt: c.startedAt,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.spa_outlined, color: kBlue),
                  label: const Text(
                    'Ways to feel calm',
                    style: TextStyle(fontSize: 15, color: kBlue, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _transcript(Conversation c) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('What you said',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: kBlue)),
          const SizedBox(height: 8),
          for (final line in c.transcript)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      _offset(line.offset),
                      style: const TextStyle(fontSize: 13, color: Colors.black45),
                    ),
                  ),
                  Expanded(
                    child: Text(line.text,
                        style: const TextStyle(fontSize: 15, height: 1.4, color: Colors.black87)),
                  ),
                ],
              ),
            ),
          const Text(
            'Only your own voice is kept. Other people in the conversation are not recorded.',
            style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.4),
          ),
        ],
      ),
    );
  }

  String _offset(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _MoodChip extends StatelessWidget {
  final StressLevel level;
  const _MoodChip({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: level.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: level.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            level.moodLabel,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}
