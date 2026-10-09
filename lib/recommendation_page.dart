import 'package:flutter/material.dart';
import 'models/recommendation.dart';
import 'models/stress_reading.dart';
import 'widgets/sally_logo.dart';

/// Suggestions for the mother based on her stress level.
///
/// Opened from the dashboard with the level that was detected. The level
/// chips at the top also let you preview the other levels in the mockup.
class RecommendationPage extends StatefulWidget {
  final StressLevel initialLevel;
  final DateTime? detectedAt;

  const RecommendationPage({
    super.key,
    this.initialLevel = StressLevel.calm,
    this.detectedAt,
  });

  @override
  State<RecommendationPage> createState() => _RecommendationPageState();
}

class _RecommendationPageState extends State<RecommendationPage> {
  static const Color logoBlue = Color(0xFF1A335D);
  static const Color cardBlue = Color(0xFFE8EEF8);
  static const Color lightGrey = Color(0xFFD9D9D9);

  late StressLevel _level;

  @override
  void initState() {
    super.initState();
    _level = widget.initialLevel;
  }

  @override
  Widget build(BuildContext context) {
    final recs = recommendationsByLevel[_level] ?? const <Recommendation>[];

    return Scaffold(
      backgroundColor: Colors.white,
      // Same navy app bar style as My Day, Ask Sally and Settings.
      appBar: AppBar(
        backgroundColor: logoBlue,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Row(
          children: [
            SallyLogo(width: 36, height: 36),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Stay Calm',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('Small steps that can help right now',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _levelSelector(),
          const SizedBox(height: 16),
          _statusBanner(),
          const SizedBox(height: 20),
          if (_level == StressLevel.high) ...[
            _supportCard(),
            const SizedBox(height: 20),
          ],
          const Text(
            'Try this now',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: logoBlue),
          ),
          const SizedBox(height: 12),
          for (final r in recs) ...[
            _recommendationTile(r),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          _disclaimer(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // Level chips: Calm / Elevated / High
  Widget _levelSelector() {
    return Row(
      children: [
        for (final lvl in StressLevel.values) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _level = lvl),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _level == lvl ? logoBlue : Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: _level == lvl ? logoBlue : lightGrey),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: lvl.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      lvl.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _level == lvl ? Colors.white : logoBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (lvl != StressLevel.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _statusBanner() {
    final isDetected = widget.detectedAt != null && _level == widget.initialLevel;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardBlue, borderRadius: BorderRadius.circular(15)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(_level.icon, color: _level.color, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stress level: ${_level.label}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (isDetected)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Detected at ${formatClock(context, widget.detectedAt!)}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  levelMessages[_level] ?? '',
                  style: const TextStyle(fontSize: 16, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Shown only for High: reach out to a real person.
  Widget _supportCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StressLevel.high.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: StressLevel.high.color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.favorite_border, color: logoBlue),
              SizedBox(width: 8),
              Text('Reach out for support',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'If stress keeps coming back or feels overwhelming, talking to someone can help.',
            style: TextStyle(fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 12),
          _contactRow(Icons.local_hospital_outlined, 'My care provider', 'Dr. (dummy contact)'),
          const SizedBox(height: 8),
          _contactRow(
            Icons.call_outlined,
            'National Maternal Mental Health Hotline',
            '1-833-TLC-MAMA (1-833-852-6262), 24/7',
          ),
        ],
      ),
    );
  }

  Widget _contactRow(IconData icon, String title, String subtitle) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calling will be enabled in a later version.')),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: logoBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recommendationTile(Recommendation r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: lightGrey),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: cardBlue,
              shape: BoxShape.circle,
            ),
            child: Icon(r.icon, color: logoBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(r.title,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: lightGrey.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${r.minutes} min', style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(r.description,
                    style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.4)),
                if (r.action == RecommendationAction.breathing) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 36,
                    child: ElevatedButton.icon(
                      onPressed: () => _openBreathing(r.minutes),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Start'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: logoBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _disclaimer() {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 16, color: Colors.black45),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            'SALLY gives wellness suggestions, not a medical diagnosis. '
            'If you feel unsafe or in crisis, call 911 or your care provider right away.',
            style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.35),
          ),
        ),
      ],
    );
  }

  void _openBreathing(int minutes) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => BreathingSheet(minutes: minutes),
    );
  }
}

/// Guided slow breathing: circle grows for 4 s (breathe in), shrinks for 6 s
/// (breathe out). Stops automatically after [minutes].
class BreathingSheet extends StatefulWidget {
  final int minutes;
  const BreathingSheet({super.key, required this.minutes});

  @override
  State<BreathingSheet> createState() => _BreathingSheetState();
}

class _BreathingSheetState extends State<BreathingSheet>
    with SingleTickerProviderStateMixin {
  static const Color logoBlue = Color(0xFF1A335D);
  static const Color cardBlue = Color(0xFFAEC0DF);
  static const int inhaleSec = 4, exhaleSec = 6;

  late final AnimationController _ctrl;
  late final int _totalCycles;
  int _cycle = 0;

  @override
  void initState() {
    super.initState();
    _totalCycles = (widget.minutes * 60 / (inhaleSec + exhaleSec)).round();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: inhaleSec + exhaleSec),
    )
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          setState(() => _cycle++);
          if (_cycle < _totalCycles) _ctrl.forward(from: 0);
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const inhaleFrac = inhaleSec / (inhaleSec + exhaleSec); // 0.4
    final done = _cycle >= _totalCycles;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Slow Breathing',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              done ? 'Well done.' : 'Breath ${_cycle + 1} of $_totalCycles',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 220,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final t = _ctrl.value;
                  final inhaling = t < inhaleFrac;
                  // 0 -> 1 while breathing in, 1 -> 0 while breathing out.
                  final p = inhaling ? t / inhaleFrac : 1 - (t - inhaleFrac) / (1 - inhaleFrac);
                  final eased = Curves.easeInOut.transform(p.clamp(0.0, 1.0));
                  final size = 100 + 110 * (done ? 0.0 : eased);

                  return Center(
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: cardBlue,
                        shape: BoxShape.circle,
                        border: Border.all(color: logoBlue, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        done ? 'Done' : (inhaling ? 'Breathe in' : 'Breathe out'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: logoBlue,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 160,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: logoBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: Text(done ? 'Close' : 'Stop',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
