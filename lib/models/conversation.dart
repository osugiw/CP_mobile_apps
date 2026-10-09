import 'stress_reading.dart';

/// One line of the transcript.
///
/// The server keeps only the owner's voice (MFCC voice diarization drops other
/// speakers before Whisper runs), so every line is something the mother said.
class TranscriptLine {
  final Duration offset; // time since the start of the conversation
  final String text;

  const TranscriptLine(this.offset, this.text);
}

/// One recorded conversation, as shown on the Conversations page.
class Conversation {
  final int id;
  final DateTime startedAt;
  final int durationMinutes;
  final String summary; // one-line headline from the LLM summary
  final int stressScore; // 0 to 100, overall voice stress for this talk
  final List<int> stressCurve; // stress samples across the talk, 0 to 100
  final List<TranscriptLine> transcript;

  const Conversation({
    required this.id,
    required this.startedAt,
    required this.durationMinutes,
    required this.summary,
    required this.stressScore,
    required this.stressCurve,
    required this.transcript,
  });

  StressLevel get level => StressLevel.fromScore(stressScore);

  /// Ready for the server. Expected JSON shape (stress fields are new):
  /// {
  ///   "id": 12, "created_at": "2026-10-08T14:05:00Z", "duration_min": 6,
  ///   "summary": {"headline": "..."},
  ///   "stress_score": 81, "stress_curve": [40, 55, 81, 70],
  ///   "transcript_lines": [{"offset_sec": 0, "text": "..."}]
  /// }
  factory Conversation.fromJson(Map<String, dynamic> j) {
    final lines = (j['transcript_lines'] as List? ?? [])
        .whereType<Map>()
        .map((l) => TranscriptLine(
              Duration(seconds: (l['offset_sec'] as num?)?.round() ?? 0),
              l['text']?.toString() ?? '',
            ))
        .toList();
    return Conversation(
      id: (j['id'] as num?)?.toInt() ?? 0,
      startedAt: DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      durationMinutes: (j['duration_min'] as num?)?.round() ?? 0,
      summary: (j['summary'] is Map ? j['summary']['headline'] : null)?.toString() ?? '',
      stressScore: (j['stress_score'] as num?)?.round() ?? 0,
      stressCurve: (j['stress_curve'] as List? ?? []).map((e) => (e as num).round()).toList(),
      transcript: lines,
    );
  }
}

/// The single place the Conversations page gets data from.
///
/// Dummy data for now. Later this can call SallyApiClient.fetchIntents
/// (it already returns transcript + summary) once the server also sends the
/// stress fields, then map each record with [Conversation.fromJson].
class ConversationRepository {
  const ConversationRepository();

  Future<List<Conversation>> fetchRecent() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return _dummy();
  }

  List<Conversation> _dummy() {
    final now = DateTime.now();
    DateTime today(int h, int m) => DateTime(now.year, now.month, now.day, h, m);
    DateTime yday(int h, int m) => today(h, m).subtract(const Duration(days: 1));
    Duration s(int sec) => Duration(seconds: sec);

    return [
      Conversation(
        id: 6,
        startedAt: today(14, 5),
        durationMinutes: 6,
        summary: 'Phone call with the insurance company about a denied ultrasound claim.',
        stressScore: 81,
        stressCurve: [45, 52, 60, 74, 88, 81, 70],
        transcript: [
          TranscriptLine(s(0), "Hi, I'm calling about a claim that was denied last week."),
          TranscriptLine(s(40), 'It was for my 20-week ultrasound. My doctor said it should be covered.'),
          TranscriptLine(s(150), "No, I already sent that form twice. I don't understand why it keeps getting rejected."),
          TranscriptLine(s(260), 'Okay. So I need a new referral number from the clinic?'),
          TranscriptLine(s(330), 'Fine. Thank you, I will call them tomorrow.'),
        ],
      ),
      Conversation(
        id: 5,
        startedAt: today(12, 10),
        durationMinutes: 15,
        summary: 'Lunch with your sister, planning the baby shower guest list.',
        stressScore: 27,
        stressCurve: [30, 25, 22, 28, 26, 24],
        transcript: [
          TranscriptLine(s(0), "I think we keep it small, maybe twenty people?"),
          TranscriptLine(s(210), "Yes! Mom will love doing the decorations."),
          TranscriptLine(s(540), "Let's do it on a Saturday afternoon in November."),
        ],
      ),
      Conversation(
        id: 4,
        startedAt: today(9, 30),
        durationMinutes: 12,
        summary: 'Talked with your partner about the nursery budget and the crib delivery.',
        stressScore: 48,
        stressCurve: [35, 40, 52, 58, 47, 42],
        transcript: [
          TranscriptLine(s(0), 'The crib is delayed again, now they say end of the month.'),
          TranscriptLine(s(180), "We're already over what we planned for the nursery."),
          TranscriptLine(s(420), "Okay, let's skip the new dresser for now and use the old one."),
        ],
      ),
      Conversation(
        id: 3,
        startedAt: yday(18, 40),
        durationMinutes: 9,
        summary: "Call with your mom about her visit next month.",
        stressScore: 35,
        stressCurve: [30, 34, 38, 36, 32],
        transcript: [
          TranscriptLine(s(0), "Hi Mom! Yes, I'm feeling better this week."),
          TranscriptLine(s(200), 'You can stay in the guest room, we cleared it out.'),
        ],
      ),
      Conversation(
        id: 2,
        startedAt: yday(11, 15),
        durationMinutes: 7,
        summary: 'Meeting with your manager about maternity leave dates and handover.',
        stressScore: 72,
        stressCurve: [40, 55, 68, 79, 72, 60],
        transcript: [
          TranscriptLine(s(0), 'I wanted to talk about my leave start date.'),
          TranscriptLine(s(120), "I know the project deadline is close, but I can't push it later."),
          TranscriptLine(s(300), "I'll write a handover document by the end of next week."),
        ],
      ),
    ];
  }
}
