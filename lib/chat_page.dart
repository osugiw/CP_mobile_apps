import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mobile_apps/widgets/sally_logo.dart';
import 'summary_page.dart'; // Import the new SummaryPage

class Transcript {
  final String date;
  final String deviceID;
  final String time;
  final String content;
  final String fatigueLevel;
  final int fillerWordsCount;
  final bool hasSummarize;

  Transcript({
    required this.date,
    required this.deviceID,
    required this.time,
    required this.content,
    required this.fatigueLevel,
    required this.fillerWordsCount,
    this.hasSummarize = true,
  });
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<Transcript> _transcripts = [
    Transcript(
      date: "March 3, 2026",
      deviceID: "BlueOwl 1",
      time: "2.00 P.M.",
      content: "Lorem ipsum LOREM IPSUM lorem ipsum Lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum",
      fatigueLevel: "x%",
      fillerWordsCount: 10,
    ),
    Transcript(
      date: "March 2, 2026",
      deviceID: "BlueOwl 1",
      time: "10.00 A.M.",
      content: "Lorem ipsum LOREM IPSUM lorem ipsum Lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum",
      fatigueLevel: "x%",
      fillerWordsCount: 5,
      hasSummarize: false,
    ),
    Transcript(
      date: "March 2, 2026",
      deviceID: "BlueOwl 1",
      time: "8.00 A.M.",
      content: "Lorem ipsum LOREM IPSUM lorem ipsum Lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum",
      fatigueLevel: "x%",
      fillerWordsCount: 8,
    ),
  ];

  void _syncTranscripts() {
    setState(() {
      _transcripts.insert(
        0,
        Transcript(
          date: "March 3, 2026",
          deviceID: "BlueOwl 1",
          time: "4.00 P.M.",
          content: "New dynamic transcription added for testing purposes. LOREM IPSUM lorem ipsum LOREM IPSUM lorem ipsum.",
          fatigueLevel: "15%",
          fillerWordsCount: 3,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            const SallyLogo(width: 40, height: 40),
            const Expanded(
              child: Center(
                child: Text(
                  'Chat',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: _syncTranscripts,
              child: SvgPicture.asset(
                'assets/images/sync-svgrepo-com.svg',
                width: 30,
                height: 30,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: Colors.grey.shade300,
            height: 1.0,
          ),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _transcripts.length,
        itemBuilder: (context, index) {
          final transcript = _transcripts[index];
          bool showDate = true;
          if (index > 0 && _transcripts[index - 1].date == transcript.date) {
            showDate = false;
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showDate)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      transcript.date,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              TranscriptCard(transcript: transcript),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }
}

class TranscriptCard extends StatelessWidget {
  final Transcript transcript;

  const TranscriptCard({super.key, required this.transcript});

  @override
  Widget build(BuildContext context) {
    const Color headerBlue = Color(0xFFAEC0DF);
    const Color contentGrey = Color(0xFFE8EEF8);
    const Color logoBlue = Color(0xFF1A335D);
    const Color limeGreen = Color(0xFF99FF66);

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: contentGrey,
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  color: headerBlue,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      transcript.deviceID,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      transcript.time,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  transcript.content,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Fatigue Level        : ${transcript.fatigueLevel}",
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  "Filler words count : ${transcript.fillerWordsCount}",
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
            if (transcript.hasSummarize)
              ElevatedButton(
                onPressed: () {
                  // Navigate to SummaryPage with data
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SummaryPage(
                        date: transcript.date,
                        deviceID: transcript.deviceID,
                        content: transcript.content,
                        fatigueLevel: transcript.fatigueLevel,
                        fillerWordsCount: transcript.fillerWordsCount,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: limeGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                ),
                child: const Text(
                  "Summarize",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
