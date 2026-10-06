import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_config.dart';
import 'widgets/sally_logo.dart';

// ── data models ───────────────────────────────────────────────────────────────

class WindowSummary {
  WindowSummary({
    required this.windowType,
    required this.windowStart,
    required this.windowEnd,
    required this.recordingCount,
    required this.transcriptCount,
    required this.summary,
    required this.intents,
    required this.generatedAt,
  });

  final String windowType;
  final String windowStart;
  final String windowEnd;
  final int    recordingCount;
  final int    transcriptCount;
  final Map<String, dynamic> summary;
  final List<dynamic>        intents;
  final String generatedAt;

  factory WindowSummary.fromJson(Map<String, dynamic> j) => WindowSummary(
        windowType:      j['window_type']?.toString()   ?? '',
        windowStart:     j['window_start']?.toString()  ?? '',
        windowEnd:       j['window_end']?.toString()    ?? '',
        recordingCount:  (j['recording_count']  as num?)?.toInt() ?? 0,
        transcriptCount: (j['transcript_count'] as num?)?.toInt() ?? 0,
        summary:  (j['summary']  as Map?)?.cast<String, dynamic>() ?? {},
        intents:  (j['intents']  as List?)  ?? [],
        generatedAt: j['generated_at']?.toString() ?? '',
      );
}

class Reminder {
  Reminder({
    required this.id,
    required this.title,
    required this.notes,
    required this.scheduledTime,
    required this.status,
    required this.repeatRule,
    this.intentId,
  });

  final int     id;
  final String  title;
  final String  notes;
  final String? scheduledTime;
  final String  status;
  final String  repeatRule;
  final int?    intentId;

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        id:            (j['id'] as num?)?.toInt() ?? 0,
        title:         j['title']?.toString()   ?? '',
        notes:         j['notes']?.toString()   ?? '',
        scheduledTime: j['scheduled_time']?.toString(),
        status:        j['status']?.toString()  ?? 'pending',
        repeatRule:    j['repeat_rule']?.toString() ?? 'none',
        intentId:      (j['intent_id'] as num?)?.toInt(),
      );
}

// ── API helper ────────────────────────────────────────────────────────────────

class _SallyDashApi {
  _SallyDashApi() {
    _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  }

  late final HttpClient _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $sallyApiToken',
        'Content-Type':  'application/json',
      };

  Future<WindowSummary> fetchWindowSummary({
    required String deviceId,
    required String window,
    bool refresh = false,
  }) async {
    final uri = Uri.parse('$sallyApiBaseUrl/summary/window').replace(
      queryParameters: {
        'device_id': deviceId,
        'window':    window,
        if (refresh) 'refresh': 'true',
      },
    );
    final req = await _client.getUrl(uri);
    _headers.forEach(req.headers.set);
    final resp = await req.close().timeout(const Duration(seconds: 90));
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode >= 400) {
      throw _apiError(resp.statusCode, body);
    }
    return WindowSummary.fromJson(
        jsonDecode(body) as Map<String, dynamic>);
  }

  Future<List<Reminder>> fetchReminders({
    required String deviceId,
    String status = 'all',
  }) async {
    final uri = Uri.parse('$sallyApiBaseUrl/reminders').replace(
      queryParameters: {'device_id': deviceId, 'status': status},
    );
    final req = await _client.getUrl(uri);
    _headers.forEach(req.headers.set);
    final resp = await req.close().timeout(const Duration(seconds: 30));
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode >= 400) throw _apiError(resp.statusCode, body);
    final list = jsonDecode(body) as List;
    return list.map((e) => Reminder.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<Reminder> createReminder({
    required String deviceId,
    required String title,
    String? notes,
    String? scheduledTime,
    int?    intentId,
  }) async {
    final uri = Uri.parse('$sallyApiBaseUrl/reminders');
    final req = await _client.postUrl(uri);
    _headers.forEach(req.headers.set);
    req.write(jsonEncode({
      'device_id': deviceId,
      'title':     title,
      if (notes != null)         'notes':          notes,
      if (scheduledTime != null) 'scheduled_time': scheduledTime,
      if (intentId != null)      'intent_id':      intentId,
    }));
    final resp = await req.close().timeout(const Duration(seconds: 30));
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode >= 400) throw _apiError(resp.statusCode, body);
    return Reminder.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<void> updateReminderStatus(int id, String status) async {
    final uri = Uri.parse('$sallyApiBaseUrl/reminders/$id');
    final req = await _client.patchUrl(uri);
    _headers.forEach(req.headers.set);
    req.write(jsonEncode({'status': status}));
    final resp = await req.close().timeout(const Duration(seconds: 15));
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode >= 400) throw _apiError(resp.statusCode, body);
  }

  Future<void> deleteReminder(int id) async {
    final uri = Uri.parse('$sallyApiBaseUrl/reminders/$id');
    final req = await _client.deleteUrl(uri);
    _headers.forEach(req.headers.set);
    final resp = await req.close().timeout(const Duration(seconds: 15));
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode >= 400) throw _apiError(resp.statusCode, body);
  }

  Exception _apiError(int code, String body) {
    try {
      final m = (jsonDecode(body) as Map)['error']?.toString();
      if (m != null && m.isNotEmpty) return Exception(m);
    } catch (_) {}
    return Exception('HTTP $code');
  }
}

// ── main page widget ──────────────────────────────────────────────────────────

class SummaryDashboardPage extends StatefulWidget {
  const SummaryDashboardPage({super.key});

  @override
  State<SummaryDashboardPage> createState() => _SummaryDashboardPageState();
}

class _SummaryDashboardPageState extends State<SummaryDashboardPage>
    with SingleTickerProviderStateMixin {
  static const Color kBlue     = Color(0xFF1A335D);
  static const Color kCardBlue = Color(0xFFE8EEF8);

  late final TabController  _tabs;
  final      _SallyDashApi  _api = _SallyDashApi();

  // 6h tab state
  bool              _loading6h  = false;
  WindowSummary?    _summary6h;
  String?           _error6h;

  // day tab state
  bool              _loadingDay  = false;
  WindowSummary?    _summaryDay;
  String?           _errorDay;

  // reminders tab state
  bool           _loadingRem  = false;
  List<Reminder> _reminders   = [];
  String?        _errorRem;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadWindow(String window, {bool refresh = false}) async {
    final is6h = window == '6h';
    setState(() {
      if (is6h) { _loading6h  = true; _error6h  = null; }
      else       { _loadingDay = true; _errorDay = null; }
    });
    try {
      final data = await _api.fetchWindowSummary(
        deviceId: sallyDeviceId,
        window:   window,
        refresh:  refresh,
      );
      if (mounted) setState(() {
        if (is6h) _summary6h  = data;
        else      _summaryDay = data;
      });
    } catch (e) {
      if (mounted) setState(() {
        if (is6h) _error6h  = e.toString();
        else      _errorDay = e.toString();
      });
    } finally {
      if (mounted) setState(() {
        if (is6h) _loading6h  = false;
        else      _loadingDay = false;
      });
    }
  }

  Future<void> _loadReminders() async {
    setState(() { _loadingRem = true; _errorRem = null; });
    try {
      final data = await _api.fetchReminders(
          deviceId: sallyDeviceId, status: 'all');
      if (mounted) setState(() => _reminders = data);
    } catch (e) {
      if (mounted) setState(() => _errorRem = e.toString());
    } finally {
      if (mounted) setState(() => _loadingRem = false);
    }
  }

  Future<void> _resolveReminder(int id) async {
    try {
      await _api.updateReminderStatus(id, 'resolved');
      await _loadReminders();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteReminder(int id) async {
    try {
      await _api.deleteReminder(id);
      await _loadReminders();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showAddReminderDialog({String? title, int? intentId}) {
    showDialog(
      context: context,
      builder: (_) => _AddReminderDialog(
        api:          _api,
        deviceId:     sallyDeviceId,
        initialTitle: title ?? '',
        intentId:     intentId,
        onCreated:    _loadReminders,
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

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
                  'Summary',
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 28,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_alarm, color: kBlue),
              tooltip: 'New Reminder',
              onPressed: _showAddReminderDialog,
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(
            children: [
              Container(color: Colors.grey.shade300, height: 1),
              TabBar(
                controller: _tabs,
                labelColor: kBlue,
                unselectedLabelColor: Colors.grey,
                indicatorColor: kBlue,
                tabs: const [
                  Tab(text: 'Last 6 Hours'),
                  Tab(text: 'Today'),
                  Tab(text: 'Reminders'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _WindowTab(
            window:   '6h',
            loading:  _loading6h,
            summary:  _summary6h,
            error:    _error6h,
            onLoad:   () => _loadWindow('6h'),
            onRefresh: () => _loadWindow('6h', refresh: true),
            onSaveReminder: _showAddReminderDialog,
          ),
          _WindowTab(
            window:   'day',
            loading:  _loadingDay,
            summary:  _summaryDay,
            error:    _errorDay,
            onLoad:   () => _loadWindow('day'),
            onRefresh: () => _loadWindow('day', refresh: true),
            onSaveReminder: _showAddReminderDialog,
          ),
          _RemindersTab(
            loading:   _loadingRem,
            reminders: _reminders,
            error:     _errorRem,
            onLoad:    _loadReminders,
            onResolve: _resolveReminder,
            onDelete:  _deleteReminder,
            onAdd:     _showAddReminderDialog,
          ),
        ],
      ),
    );
  }
}

// ── window summary tab ────────────────────────────────────────────────────────

class _WindowTab extends StatelessWidget {
  static const Color kBlue     = Color(0xFF1A335D);
  static const Color kCardBlue = Color(0xFFE8EEF8);

  final String            window;
  final bool              loading;
  final WindowSummary?    summary;
  final String?           error;
  final VoidCallback      onLoad;
  final VoidCallback      onRefresh;
  final void Function({String? title, int? intentId}) onSaveReminder;

  const _WindowTab({
    required this.window,
    required this.loading,
    this.summary,
    this.error,
    required this.onLoad,
    required this.onRefresh,
    required this.onSaveReminder,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: kBlue));
    }
    if (error != null) {
      return _ErrorState(message: error!, onRetry: onLoad);
    }
    if (summary == null) {
      return _EmptyState(
        label: window == '6h' ? 'Load Last 6 Hours' : "Load Today's Summary",
        onLoad: onLoad,
      );
    }

    final s           = summary!.summary;
    final intents     = summary!.intents;
    final actionItems = (s['action_items']     as List?) ?? [];
    final topics      = (s['topics']           as List?) ?? [];
    final quotes      = (s['notable_quotes']   as List?) ?? [];
    final suggested   = (s['suggested_reminders'] as List?) ?? [];

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: kBlue,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Headline card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: kBlue, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s['headline']?.toString() ?? '',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      height: 1.3),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.mood, color: Colors.white60, size: 15),
                  const SizedBox(width: 4),
                  Text('Mood: ${s['mood'] ?? 'unknown'}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13)),
                  const SizedBox(width: 14),
                  const Icon(Icons.hearing, color: Colors.white60, size: 15),
                  const SizedBox(width: 4),
                  Text(
                      '${summary!.transcriptCount} clip'
                      '${summary!.transcriptCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Summary paragraph
          if ((s['summary'] as String? ?? '').isNotEmpty) ...[
            _sectionTitle('Summary'),
            const SizedBox(height: 8),
            Text(s['summary'].toString(),
                style: const TextStyle(fontSize: 15, height: 1.5)),
            const SizedBox(height: 20),
          ],

          // Topics
          if (topics.isNotEmpty) ...[
            _sectionTitle('Topics'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 4,
              children: topics
                  .map((t) => Chip(
                        label: Text(t.toString(),
                            style: const TextStyle(
                                fontSize: 12, color: kBlue)),
                        backgroundColor: kCardBlue,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
          ],

          // Action items
          if (actionItems.isNotEmpty) ...[
            _sectionTitle('Action Items'),
            const SizedBox(height: 4),
            ...actionItems.map((a) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle_outline,
                      color: kBlue, size: 22),
                  title: Text(a.toString()),
                  trailing: IconButton(
                    icon: const Icon(Icons.alarm_add, color: kBlue, size: 20),
                    tooltip: 'Save as Reminder',
                    onPressed: () =>
                        onSaveReminder(title: a.toString()),
                  ),
                )),
            const SizedBox(height: 12),
          ],

          // Intents
          if (intents.isNotEmpty) ...[
            _sectionTitle('Detected Intents'),
            const SizedBox(height: 4),
            ...intents.take(8).map((i) {
              final conf = (i['fused_confidence'] as num?) ?? 0;
              final dec  = i['decision'] as String? ?? '';
              final task = i['task']?.toString() ?? '';
              final id   = (i['id'] as num?)?.toInt();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: kCardBlue,
                    borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Icon(
                    dec == 'act'
                        ? Icons.priority_high
                        : Icons.info_outline,
                    color:
                        dec == 'act' ? Colors.red : Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        Text(
                          '${i['intent_type']} • '
                          '${(conf * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: kBlue,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: () =>
                        onSaveReminder(title: task, intentId: id),
                    child: const Text('Remind',
                        style: TextStyle(fontSize: 12)),
                  ),
                ]),
              );
            }),
            const SizedBox(height: 12),
          ],

          // Notable quotes
          if (quotes.isNotEmpty) ...[
            _sectionTitle('Notable Quotes'),
            const SizedBox(height: 8),
            ...quotes.map((q) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      border: Border(
                          left: BorderSide(color: kBlue, width: 3)),
                      color: Colors.grey.shade50),
                  child: Text('"${q.toString()}"',
                      style: const TextStyle(
                          fontStyle: FontStyle.italic, fontSize: 14)),
                )),
            const SizedBox(height: 12),
          ],

          // Suggested reminders
          if (suggested.isNotEmpty) ...[
            _sectionTitle('Suggested Reminders'),
            const SizedBox(height: 4),
            ...suggested.take(3).map((sr) {
              final title  = sr['title']?.toString()  ?? '';
              if (title.isEmpty) return const SizedBox.shrink();
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lightbulb_outline,
                    color: Colors.amber, size: 22),
                title: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600)),
                subtitle: (sr['reason']?.toString() ?? '').isNotEmpty
                    ? Text(sr['reason'].toString())
                    : null,
                trailing: IconButton(
                  icon: const Icon(Icons.add_alarm,
                      color: kBlue, size: 20),
                  onPressed: () => onSaveReminder(title: title),
                ),
              );
            }),
            const SizedBox(height: 12),
          ],

          // Refresh + metadata
          Center(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: kBlue,
                  side: const BorderSide(color: kBlue)),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Regenerate'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Generated: ${_fmtTs(summary!.generatedAt)}',
              style: TextStyle(
                  color: Colors.grey.shade400, fontSize: 11),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(text,
      style: const TextStyle(
          fontWeight: FontWeight.bold, fontSize: 16, color: kBlue));

  String _fmtTs(String ts) {
    if (ts.length >= 16) return ts.substring(0, 16).replaceAll('T', ' ');
    return ts;
  }
}

// ── reminders tab ─────────────────────────────────────────────────────────────

class _RemindersTab extends StatelessWidget {
  static const Color kBlue = Color(0xFF1A335D);

  final bool           loading;
  final List<Reminder> reminders;
  final String?        error;
  final VoidCallback   onLoad;
  final Future<void>   Function(int id) onResolve;
  final Future<void>   Function(int id) onDelete;
  final void Function({String? title, int? intentId}) onAdd;

  const _RemindersTab({
    required this.loading,
    required this.reminders,
    this.error,
    required this.onLoad,
    required this.onResolve,
    required this.onDelete,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: kBlue));
    }
    if (error != null) {
      return _ErrorState(message: error!, onRetry: onLoad);
    }
    if (reminders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.alarm_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No reminders yet.',
                style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => onLoad(),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    final pending  = reminders.where((r) => r.status == 'pending').toList();
    final resolved = reminders.where((r) => r.status != 'pending').toList();

    return RefreshIndicator(
      onRefresh: () async => onLoad(),
      color: kBlue,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (pending.isNotEmpty) ...[
            _sectionTitle('Pending'),
            const SizedBox(height: 8),
            ...pending.map((r) => _ReminderCard(
                  reminder:  r,
                  onResolve: () => onResolve(r.id),
                  onDelete:  () => onDelete(r.id),
                )),
            const SizedBox(height: 20),
          ],
          if (resolved.isNotEmpty) ...[
            _sectionTitle('Resolved', grey: true),
            const SizedBox(height: 8),
            ...resolved.map((r) => _ReminderCard(reminder: r)),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, {bool grey = false}) => Text(
        text,
        style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: grey ? Colors.grey : kBlue),
      );
}

class _ReminderCard extends StatelessWidget {
  final Reminder     reminder;
  final VoidCallback? onResolve;
  final VoidCallback? onDelete;

  const _ReminderCard({
    required this.reminder,
    this.onResolve,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = reminder.status != 'pending';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              resolved ? Icons.check_circle : Icons.alarm,
              color: resolved
                  ? Colors.green
                  : const Color(0xFF1A335D),
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminder.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      decoration:
                          resolved ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if ((reminder.notes ?? '').isNotEmpty)
                    Text(reminder.notes,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  if (reminder.scheduledTime != null)
                    Text(
                      _fmtTs(reminder.scheduledTime!),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black45),
                    ),
                ],
              ),
            ),
            if (onResolve != null)
              TextButton(
                onPressed: onResolve,
                child: const Text('Done',
                    style: TextStyle(
                        color: Color(0xFF1A335D), fontSize: 13)),
              ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.red, size: 20),
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
          ],
        ),
      ),
    );
  }

  String _fmtTs(String ts) {
    if (ts.length >= 16) return ts.substring(0, 16).replaceAll('T', ' ');
    return ts;
  }
}

// ── shared helper widgets ─────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String    message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final String    label;
  final VoidCallback onLoad;
  const _EmptyState({required this.label, required this.onLoad});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No summary loaded yet.',
                style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A335D)),
              onPressed: onLoad,
              icon: const Icon(Icons.download),
              label: Text(label),
            ),
          ],
        ),
      );
}

// ── add reminder dialog ───────────────────────────────────────────────────────

class _AddReminderDialog extends StatefulWidget {
  final _SallyDashApi api;
  final String        deviceId;
  final String        initialTitle;
  final int?          intentId;
  final VoidCallback  onCreated;

  const _AddReminderDialog({
    required this.api,
    required this.deviceId,
    required this.initialTitle,
    this.intentId,
    required this.onCreated,
  });

  @override
  State<_AddReminderDialog> createState() => _AddReminderDialogState();
}

class _AddReminderDialogState extends State<_AddReminderDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _notesCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Reminder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            maxLength: 500,
            decoration: const InputDecoration(
                labelText: 'Title', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.api.createReminder(
        deviceId: widget.deviceId,
        title:    title,
        notes:    _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
        intentId: widget.intentId,
      );
      widget.onCreated();
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reminder saved!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
