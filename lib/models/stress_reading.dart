import 'package:flutter/material.dart';

/// Three stress bands used across the app.
///
/// Each level carries its own label, color and icon, so every screen
/// (dashboard card, chart, recommendation page) shows a level the same way.
/// Score thresholds live in [StressLevel.fromScore].
enum StressLevel {
  calm('Calm', 'Relaxed', Color(0xFF7FB77E), Icons.spa_outlined),
  elevated('Elevated', 'Some tension', Color(0xFFE8B04B), Icons.waves),
  high('High', 'Tense moment', Color(0xFFE07A5F), Icons.priority_high_rounded);

  const StressLevel(this.label, this.moodLabel, this.color, this.icon);

  final String label; // short level name for charts and chips
  final String moodLabel; // gentle wording shown on conversation cards
  final Color color;
  final IconData icon;

  /// Score is 0 to 100. Change the thresholds here once the model is calibrated.
  static StressLevel fromScore(int score) {
    if (score >= 70) return StressLevel.high;
    if (score >= 40) return StressLevel.elevated;
    return StressLevel.calm;
  }
}

/// One stress estimate for one recorded conversation segment.
class StressReading {
  final DateTime timestamp;
  final int score; // 0 to 100
  final int durationMinutes; // length of the analysed segment
  final String source; // e.g. "Conversation"

  const StressReading({
    required this.timestamp,
    required this.score,
    required this.durationMinutes,
    this.source = 'Conversation',
  });

  StressLevel get level => StressLevel.fromScore(score);

  /// Ready for the server. Expected JSON shape:
  /// {"timestamp": "2026-10-08T14:05:00", "score": 81, "duration_min": 6, "source": "Conversation"}
  factory StressReading.fromJson(Map<String, dynamic> json) {
    return StressReading(
      timestamp: DateTime.parse(json['timestamp'] as String),
      score: (json['score'] as num).round(),
      durationMinutes: (json['duration_min'] as num?)?.round() ?? 0,
      source: json['source'] as String? ?? 'Conversation',
    );
  }
}

/// The single place the UI gets stress data from.
///
/// For now it returns dummy data. When the server is ready, only the body of
/// [fetchToday] needs to change (for example an HTTP GET to the RPi5 server),
/// and the screens keep working as they are.
class StressRepository {
  const StressRepository();

  Future<List<StressReading>> fetchToday() async {
    // Simulated network delay so the loading state is visible in the mockup.
    await Future.delayed(const Duration(milliseconds: 400));

    // TODO(server): replace with something like
    //   final res = await http.get(Uri.parse('$baseUrl/api/stress?date=$today'));
    //   final list = jsonDecode(res.body) as List;
    //   return list.map((e) => StressReading.fromJson(e)).toList();
    return _dummyReadings();
  }

  List<StressReading> _dummyReadings() {
    final now = DateTime.now();
    DateTime at(int h, int m) => DateTime(now.year, now.month, now.day, h, m);

    return [
      StressReading(timestamp: at(7, 15), score: 22, durationMinutes: 4),
      StressReading(timestamp: at(8, 40), score: 35, durationMinutes: 9),
      StressReading(timestamp: at(9, 30), score: 48, durationMinutes: 12),
      StressReading(timestamp: at(10, 50), score: 31, durationMinutes: 6),
      StressReading(timestamp: at(12, 10), score: 27, durationMinutes: 15),
      StressReading(timestamp: at(13, 25), score: 74, durationMinutes: 8),
      StressReading(timestamp: at(14, 5), score: 81, durationMinutes: 6),
      StressReading(timestamp: at(15, 40), score: 55, durationMinutes: 10),
      StressReading(timestamp: at(17, 20), score: 38, durationMinutes: 7),
      StressReading(timestamp: at(18, 45), score: 44, durationMinutes: 11),
      StressReading(timestamp: at(20, 10), score: 29, durationMinutes: 5),
    ];
  }
}

/// "2:05 PM" style time, using the phone's locale (no extra package needed).
String formatClock(BuildContext context, DateTime t) {
  return TimeOfDay.fromDateTime(t).format(context);
}
