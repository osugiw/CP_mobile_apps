import 'package:flutter/material.dart';

class SummaryPage extends StatelessWidget {
  final String date;
  final String deviceID;
  final String content;
  final String fatigueLevel;
  final int fillerWordsCount;

  const SummaryPage({
    super.key,
    required this.date,
    required this.deviceID,
    required this.content,
    required this.fatigueLevel,
    required this.fillerWordsCount,
  });

  @override
  Widget build(BuildContext context) {
    const Color logoBlue = Color(0xFF1A335D);
    const Color lightGrey = Color(0xFFD9D9D9);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false, // Remove default back button
        title: Center(
          child: Text(
            date,
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Summary of Talk',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              // Summary Content Container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: lightGrey,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  content,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.red, // Highlighting part of the design
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'People in the Conversation',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildSpeakerCircle(const Color(0xFFE53935), "You"),
                  const SizedBox(width: 40),
                  _buildSpeakerCircle(const Color(0xFF388E3C), "Speaker 2"),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Other Analytics',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildAnalyticsBox(fillerWordsCount.toString(), "Counts", "Filler Words"),
                  const SizedBox(width: 12),
                  _buildAnalyticsBox("10", "Seconds", "Pausing"),
                  const SizedBox(width: 12),
                  _buildAnalyticsBox("1.30", "One hour thirty minutes", "Active time", isWide: true),
                ],
              ),
              const SizedBox(height: 40),
              // Back Button
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

  Widget _buildSpeakerCircle(Color color, String label) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildAnalyticsBox(String value, String subValue, String label, {bool isWide = false}) {
    return Column(
      children: [
        Container(
          width: isWide ? 120 : 70,
          height: 70,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFD9D9D9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                subValue,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 9, color: Colors.black54),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
