import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'widgets/sally_logo.dart';

// ── data model ────────────────────────────────────────────────────────────────

class TaskReminder {
  TaskReminder({
    required this.id,
    required this.title,
    required this.notes,
    required this.status,
    required this.scheduledTime,
  });

  final int     id;
  final String  title;
  final String  notes;
  final String  status;
  final String? scheduledTime;

  factory TaskReminder.fromJson(Map<String, dynamic> j) => TaskReminder(
        id:            (j['id'] as num?)?.toInt() ?? 0,
        title:         j['title']?.toString()  ?? '',
        notes:         j['notes']?.toString()  ?? '',
        status:        j['status']?.toString() ?? 'pending',
        scheduledTime: j['scheduled_time']?.toString(),
      );
}

// ── API ───────────────────────────────────────────────────────────────────────

class _TasksApi {
  _TasksApi() {
    _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  }
  late final HttpClient _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $sallyApiToken',
        'Content-Type': 'application/json',
      };

  Future<List<TaskReminder>> fetchPending(String deviceId) async {
    final uri = Uri.parse('$sallyApiBaseUrl/reminders').replace(
      queryParameters: {'device_id': deviceId, 'status': 'pending'},
    );
    final req = await _client.getUrl(uri);
    _headers.forEach(req.headers.set);
    final resp = await req.close().timeout(const Duration(seconds: 20));
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode >= 400) throw Exception('HTTP ${resp.statusCode}');
    final list = jsonDecode(body) as List;
    return list.map((e) => TaskReminder.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> markDone(int id) async {
    final uri = Uri.parse('$sallyApiBaseUrl/reminders/$id');
    final req = await _client.patchUrl(uri);
    _headers.forEach(req.headers.set);
    req.write(jsonEncode({'status': 'resolved'}));
    final resp = await req.close().timeout(const Duration(seconds: 15));
    if (resp.statusCode >= 400) {
      final body = await resp.transform(utf8.decoder).join();
      throw Exception('HTTP ${resp.statusCode}: $body');
    }
  }

  Future<void> addTask({
    required String deviceId,
    required String title,
    String? notes,
  }) async {
    final uri = Uri.parse('$sallyApiBaseUrl/reminders');
    final req = await _client.postUrl(uri);
    _headers.forEach(req.headers.set);
    req.write(jsonEncode({
      'device_id': deviceId,
      'title': title,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    }));
    final resp = await req.close().timeout(const Duration(seconds: 20));
    if (resp.statusCode >= 400) {
      final body = await resp.transform(utf8.decoder).join();
      throw Exception('HTTP ${resp.statusCode}: $body');
    }
  }
}

// ── page ──────────────────────────────────────────────────────────────────────

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  static const Color kBlue  = Color(0xFF1A335D);
  static const Color kGreen = Color(0xFF2E7D32);

  final _TasksApi _api = _TasksApi();
  List<TaskReminder> _tasks = [];
  bool   _loading = true;
  String? _error;
  String  _patientName = '';

  @override
  void initState() {
    super.initState();
    _loadName();
    _loadTasks();
  }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _patientName = prefs.getString('patient_name') ?? '');
  }

  Future<void> _loadTasks() async {
    setState(() { _loading = true; _error = null; });
    try {
      final tasks = await _api.fetchPending(sallyDeviceId);
      if (mounted) setState(() { _tasks = tasks; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _markDone(TaskReminder task) async {
    try {
      await _api.markDone(task.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Great job! Task completed.', style: TextStyle(fontSize: 16)),
            backgroundColor: kGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await _loadTasks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update: $e')));
      }
    }
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (_) => _AddTaskDialog(
        api: _api,
        deviceId: sallyDeviceId,
        onAdded: _loadTasks,
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final greeting = _patientName.isNotEmpty
        ? '${_greeting()}, $_patientName!'
        : '${_greeting()}!';

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
                  Text(
                    greeting,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Here are your tasks',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white, size: 28),
              onPressed: _loadTasks,
              tooltip: 'Refresh',
            ),
          ],
        ),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: kBlue,
        icon: const Icon(Icons.add, color: Colors.white, size: 28),
        label: const Text('Add Task', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF1A335D)),
            SizedBox(height: 16),
            Text('Loading your tasks...', style: TextStyle(fontSize: 18, color: Colors.black54)),
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
                'Could not load tasks.\nCheck your connection.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.black54, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _loadTasks,
                  icon: const Icon(Icons.refresh, size: 24),
                  label: const Text('Try Again', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A335D),
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

    if (_tasks.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadTasks,
        color: const Color(0xFF1A335D),
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 80, color: Colors.green.shade300),
                    const SizedBox(height: 20),
                    const Text(
                      'All done for today!',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A335D)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You have no tasks right now.',
                      style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTasks,
      color: const Color(0xFF1A335D),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _tasks.length,
        itemBuilder: (context, i) => _TaskCard(
          task: _tasks[i],
          onDone: () => _markDone(_tasks[i]),
        ),
      ),
    );
  }
}

// ── task card ─────────────────────────────────────────────────────────────────

class _TaskCard extends StatelessWidget {
  final TaskReminder task;
  final VoidCallback onDone;

  const _TaskCard({required this.task, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1A335D).withValues(alpha: 0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.alarm, color: Color(0xFF1A335D), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    task.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            if (task.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 40),
                child: Text(
                  task.notes,
                  style: const TextStyle(fontSize: 16, color: Colors.black54, height: 1.4),
                ),
              ),
            ],
            if (task.scheduledTime != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 40),
                child: Row(
                  children: [
                    const Icon(Icons.access_time, size: 16, color: Colors.black38),
                    const SizedBox(width: 4),
                    Text(
                      _fmtTime(task.scheduledTime!),
                      style: const TextStyle(fontSize: 14, color: Colors.black45),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: onDone,
                icon: const Icon(Icons.check_circle_outline, size: 26),
                label: const Text('I Did This!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTime(String ts) {
    if (ts.length >= 16) return ts.substring(0, 16).replaceAll('T', ' ');
    return ts;
  }
}

// ── add task dialog ───────────────────────────────────────────────────────────

class _AddTaskDialog extends StatefulWidget {
  final _TasksApi    api;
  final String       deviceId;
  final VoidCallback onAdded;

  const _AddTaskDialog({
    required this.api,
    required this.deviceId,
    required this.onAdded,
  });

  @override
  State<_AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<_AddTaskDialog> {
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('New Task', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A335D))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
              labelText: 'What do you need to do?',
              labelStyle: TextStyle(fontSize: 16),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              labelText: 'Extra notes (optional)',
              labelStyle: TextStyle(fontSize: 15),
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(fontSize: 16)),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A335D),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save Task', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.api.addTask(
        deviceId: widget.deviceId,
        title: title,
        notes: _notesCtrl.text.trim(),
      );
      widget.onAdded();
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task added!', style: TextStyle(fontSize: 16))));
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
