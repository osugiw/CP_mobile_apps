import 'package:flutter/material.dart';
import '../models/stress_reading.dart';
import '../recommendation_page.dart';
import 'sally_button.dart';
import 'stress_timeline_chart.dart';

/// Dashboard card: current stress level, today's timeline with timestamps,
/// and a list of recent stress events.
class StressAnalysisCard extends StatefulWidget {
  final StressRepository repository;

  const StressAnalysisCard({super.key, this.repository = const StressRepository()});

  @override
  State<StressAnalysisCard> createState() => _StressAnalysisCardState();
}

class _StressAnalysisCardState extends State<StressAnalysisCard> {
  static const Color logoBlue = Color(0xFF1A335D);
  static const Color cardBlue = Color(0xFFE8EEF8); // same light blue as My Day cards

  late Future<List<StressReading>> _future;
  int? _selected;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchToday();
  }

  void _openRecommendations(StressReading reading) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecommendationPage(
          initialLevel: reading.level,
          detectedAt: reading.timestamp,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: FutureBuilder<List<StressReading>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator(color: logoBlue)),
            );
          }
          if (snap.hasError || (snap.data ?? []).isEmpty) {
            return const SizedBox(
              height: 120,
              child: Center(child: Text('No stress data yet today')),
            );
          }
          return _buildContent(snap.data!);
        },
      ),
    );
  }

  Widget _buildContent(List<StressReading> readings) {
    final latest = readings.last;
    final selectedIdx = _selected ?? readings.length - 1;
    final selected = readings[selectedIdx];

    final avg = readings.map((r) => r.score).reduce((a, b) => a + b) / readings.length;
    final peak = readings.reduce((a, b) => a.score >= b.score ? a : b);
    final highCount = readings.where((r) => r.level == StressLevel.high).length;

    // Newest first for the event list.
    final events = readings.reversed.toList();
    final visibleEvents = _showAll ? events : events.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.favorite_outline, color: logoBlue, size: 26),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Your Stress Today',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: logoBlue),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'From your voice · last updated ${formatClock(context, latest.timestamp)}',
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 12),

        // Current level
        _whiteBox(
          child: Row(
            children: [
              _scoreCircle(latest),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Current level',
                        style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 2),
                    Text(
                      latest.level.moodLabel,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: latest.level.color,
                      ),
                    ),
                    Text(
                      '${latest.source} at ${formatClock(context, latest.timestamp)}',
                      style: const TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Summary stats
        Row(
          children: [
            Expanded(child: _statTile('${avg.round()}', 'Average')),
            const SizedBox(width: 8),
            Expanded(
              child: _statTile('${peak.score}', 'Peak at ${formatClock(context, peak.timestamp)}'),
            ),
            const SizedBox(width: 8),
            Expanded(child: _statTile('$highCount', 'High events')),
          ],
        ),
        const SizedBox(height: 12),

        // Timeline chart
        _whiteBox(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 6, bottom: 6),
                child: Text('Stress over time',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              StressTimelineChart(
                readings: readings,
                selectedIndex: selectedIdx,
                onSelect: (i) => setState(() => _selected = i),
              ),
              const SizedBox(height: 8),
              // Detail of the selected point, so every dot has a readable timestamp.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: selected.level.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: selected.level.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${formatClock(context, selected.timestamp)}  ·  '
                        'Score ${selected.score}  ·  ${selected.level.label}  ·  '
                        '${selected.durationMinutes} min',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Event list with timestamps
        const Text('Recent moments',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: logoBlue)),
        const SizedBox(height: 8),
        _whiteBox(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < visibleEvents.length; i++) ...[
                if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
                _eventRow(visibleEvents[i]),
              ],
            ],
          ),
        ),
        if (events.length > 4)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Text(
                _showAll ? 'Show less' : 'Show all ${events.length} moments',
                style: const TextStyle(color: logoBlue, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Center(
          child: SallyButton(
            text: 'Ways to Stay Calm',
            onPressed: () => _openRecommendations(latest),
          ),
        ),
      ],
    );
  }

  // Small building blocks

  Widget _whiteBox({required Widget child, EdgeInsets padding = const EdgeInsets.all(12)}) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _scoreCircle(StressReading r) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              value: r.score / 100,
              strokeWidth: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(r.level.color),
            ),
          ),
          Text(
            '${r.score}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: logoBlue),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: logoBlue)),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _eventRow(StressReading r) {
    return InkWell(
      onTap: () => _openRecommendations(r),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                formatClock(context, r.timestamp),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: r.level.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${r.level.moodLabel} · ${r.durationMinutes} min',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Text('${r.score}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: logoBlue)),
            const Icon(Icons.chevron_right, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}
