import 'package:flutter/material.dart';

class SummaryPage extends StatelessWidget {
  const SummaryPage({
    super.key,
    required this.dateLabel,
    required this.deviceId,
    required this.transcript,
    required this.summaryText,
    required this.headline,
    required this.intentType,
    required this.decision,
    required this.confidenceLabel,
    required this.scheduledTimeLabel,
    required this.peopleMentioned,
    required this.topics,
  });

  final String dateLabel;
  final String deviceId;
  final String transcript;
  final String summaryText;
  final String headline;
  final String intentType;
  final String decision;
  final String confidenceLabel;
  final String scheduledTimeLabel;
  final List<String> peopleMentioned;
  final List<String> topics;

  @override
  Widget build(BuildContext context) {
    const Color lightGrey = Color(0xFFD9D9D9);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Center(
          child: Text(
            dateLabel,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: Colors.grey.shade300,
            height: 1.0,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  'Summary of Talk',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  deviceId,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
              ),
              if (headline.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  headline,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _buildSectionCard(
                lightGrey,
                summaryText.trim().isEmpty
                    ? 'No summary returned yet. Open the transcript below for the raw text.'
                    : summaryText,
              ),
              const SizedBox(height: 24),
              const Text(
                'Intent Details',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildAnalyticsBox(_titleCase(intentType), 'Detected', 'Intent Type'),
                  _buildAnalyticsBox(_titleCase(decision), 'Server Action', 'Decision'),
                  _buildAnalyticsBox(confidenceLabel, 'Fused Score', 'Confidence'),
                  _buildAnalyticsBox(scheduledTimeLabel, 'Reminder Time', 'Schedule', isWide: true),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'People Mentioned',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              _buildTagList(
                tags: peopleMentioned,
                emptyText: 'No people were extracted from this summary.',
              ),
              const SizedBox(height: 24),
              const Text(
                'Topics',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              _buildTagList(
                tags: topics,
                emptyText: 'No summary topics were returned.',
              ),
              const SizedBox(height: 24),
              const Text(
                'Transcript',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              _buildSectionCard(lightGrey, transcript),
              const SizedBox(height: 40),
              SizedBox(
                width: 160,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: lightGrey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Back',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(Color color, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.black87,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildTagList({
    required List<String> tags,
    required String emptyText,
  }) {
    if (tags.isEmpty) {
      return Text(
        emptyText,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.black54,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags
          .map(
            (tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE8EEF8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                tag,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildAnalyticsBox(
    String value,
    String subValue,
    String label, {
    bool isWide = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: isWide ? 160 : 120,
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFD9D9D9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                subValue,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: Colors.black54),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: isWide ? 160 : 120,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  String _titleCase(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Unknown';
    }

    return trimmed
        .split(RegExp(r'[_\s]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
        .join(' ');
  }
}
