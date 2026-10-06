import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_config.dart';
import 'widgets/sally_logo.dart';

// ── lightweight API helper ────────────────────────────────────────────────────

class _DayApi {
  _DayApi() {
    _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  }
  late final HttpClient _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $sallyApiToken',
        'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>> fetchDaySummary({
    required String deviceId,
    bool refresh = false,
  }) async {
    final uri = Uri.parse('$sallyApiBaseUrl/summary/window').replace(
      queryParameters: {
        'device_id': deviceId,
        'window': 'day',
        if (refresh) 'refresh': 'true',
      },
    );
    final req = await _client.getUrl(uri);
    _headers.forEach(req.headers.set);
    final resp = await req.close().timeout(const Duration(seconds: 90));
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode >= 400) throw Exception('HTTP ${resp.statusCode}');
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  }
}

// ── page ──────────────────────────────────────────────────────────────────────

class MyDayPage extends StatefulWidget {
  const MyDayPage({super.key});

  @override
  State<MyDayPage> createState() => _MyDayPageState();
}

class _MyDayPageState extends State<MyDayPage> {
  static const Color kBlue     = Color(0xFF1A335D);
  static const Color kCardBlue = Color(0xFFE8EEF8);

  final _DayApi _api = _DayApi();
  Map<String, dynamic>? _data;
  bool   _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _api.fetchDaySummary(deviceId: sallyDeviceId, refresh: refresh);
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _dateLabel() {
    final now = DateTime.now();
    const months = ['January','February','March','April','May','June',
                    'July','August','September','October','November','December'];
    const days   = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    final dayName = days[now.weekday - 1];
    return '$dayName, ${months[now.month - 1]} ${now.day}';
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('My Day', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  Text(_dateLabel(), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white, size: 28),
              onPressed: () => _load(refresh: true),
              tooltip: 'Refresh',
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: kBlue),
            SizedBox(height: 16),
            Text('Summarising your day...', style: TextStyle(fontSize: 18, color: Colors.black54)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Could not load your summary.\nCheck your connection.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.black54, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 24),
                  label: const Text('Try Again', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_data == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wb_sunny_outlined, size: 72, color: Colors.amber.shade300),
            const SizedBox(height: 20),
            const Text('No summary yet today.', style: TextStyle(fontSize: 20, color: Colors.black54)),
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.download, size: 24),
                label: const Text('Load My Day', style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final summaryMap  = (_data!['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final headline    = summaryMap['headline']?.toString() ?? '';
    final summaryText = summaryMap['summary']?.toString()  ?? '';
    final mood        = summaryMap['mood']?.toString()     ?? '';
    final topics      = (summaryMap['topics'] as List?)    ?? [];
    final actions     = (summaryMap['action_items'] as List?) ?? [];

    return RefreshIndicator(
      onRefresh: () async => _load(refresh: true),
      color: kBlue,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Headline banner
          if (headline.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kBlue,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                headline,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Mood pill
          if (mood.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.mood, color: kBlue, size: 26),
                const SizedBox(width: 10),
                Text(
                  'Mood: $mood',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: kBlue),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          // Summary text
          if (summaryText.isNotEmpty) ...[
            _sectionTitle('What happened today'),
            const SizedBox(height: 10),
            Text(summaryText, style: const TextStyle(fontSize: 18, height: 1.6, color: Colors.black87)),
            const SizedBox(height: 24),
          ],

          // Topics
          if (topics.isNotEmpty) ...[
            _sectionTitle('Things you talked about'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: topics.map((t) => Chip(
                label: Text(t.toString(), style: const TextStyle(fontSize: 15, color: kBlue)),
                backgroundColor: kCardBlue,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              )).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // Action items / reminders from today
          if (actions.isNotEmpty) ...[
            _sectionTitle('Things you mentioned doing'),
            const SizedBox(height: 10),
            ...actions.map((a) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: kCardBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.arrow_right, color: kBlue, size: 26),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(a.toString(), style: const TextStyle(fontSize: 17, height: 1.3)),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 24),
          ],

          // Refresh footer
          Center(
            child: OutlinedButton.icon(
              onPressed: () => _load(refresh: true),
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('Refresh Summary', style: TextStyle(fontSize: 16)),
              style: OutlinedButton.styleFrom(
                foregroundColor: kBlue,
                side: const BorderSide(color: kBlue),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: kBlue,
        ),
      );
}
