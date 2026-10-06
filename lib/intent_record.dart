class IntentRecord {
  IntentRecord({
    required this.id,
    required this.recordingId,
    required this.task,
    required this.intentType,
    required this.temporalCue,
    required this.fusedConfidence,
    required this.decision,
    required this.status,
    required this.scheduledTime,
    required this.deviceId,
    required this.createdAt,
    required this.transcript,
    required this.summaryPayload,
  });

  final int id;
  final int? recordingId;
  final String task;
  final String intentType;
  final String temporalCue;
  final double? fusedConfidence;
  final String decision;
  final String status;
  final DateTime? scheduledTime;
  final String deviceId;
  final DateTime? createdAt;
  final String? transcript;
  final Map<String, dynamic>? summaryPayload;

  factory IntentRecord.fromJson(Map<String, dynamic> json) {
    final dynamic rawSummary = json['summary'];

    return IntentRecord(
      id: _readInt(json['id']) ?? 0,
      recordingId: _readInt(json['recording_id']),
      task: _readString(json['task']),
      intentType: _readString(json['intent_type']),
      temporalCue: _readString(json['temporal_cue']),
      fusedConfidence: _readDouble(json['fused_confidence']),
      decision: _readString(json['decision']),
      status: _readString(json['status']),
      scheduledTime: _readDateTime(json['scheduled_time']),
      deviceId: _readString(json['device_id']),
      createdAt: _readDateTime(json['created_at']),
      transcript: _readNullableString(json['transcript']),
      summaryPayload: rawSummary is Map
          ? Map<String, dynamic>.from(rawSummary)
          : null,
    );
  }

  String get transcriptText {
    final value = transcript?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
    if (task.trim().isNotEmpty) {
      return task.trim();
    }
    return 'No transcript available yet.';
  }

  String get headline {
    final dynamic value = summaryPayload?['headline'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return task.trim();
  }

  String get summaryText {
    final dynamic value = summaryPayload?['summary'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return '';
  }

  List<String> get topics => _readStringList(summaryPayload?['topics']);

  List<String> get peopleMentioned =>
      _readStringList(summaryPayload?['people_mentioned']);

  bool get hasSummary => summaryText.isNotEmpty || headline.isNotEmpty;

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static double? _readDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  static String _readString(dynamic value) {
    if (value is String) {
      return value;
    }
    return value?.toString() ?? '';
  }

  static String? _readNullableString(dynamic value) {
    if (value == null) {
      return null;
    }
    final text = _readString(value).trim();
    return text.isEmpty ? null : text;
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  static List<String> _readStringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }
}
