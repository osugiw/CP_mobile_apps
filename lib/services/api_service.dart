import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton HTTP client for all Sally Pi server calls.
/// Configure the server URL, API token, and device ID via [configure].
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  // ── config keys stored in SharedPreferences ──────────────────────────────

  static const _keyUrl      = 'pi_url';
  static const _keyToken    = 'api_token';
  static const _keyDeviceId = 'device_id';

  Future<void> configure({
    required String piUrl,
    required String apiToken,
    required String deviceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUrl,      piUrl);
    await prefs.setString(_keyToken,    apiToken);
    await prefs.setString(_keyDeviceId, deviceId);
  }

  Future<String> get baseUrl async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUrl) ?? 'http://192.168.1.100:5000';
  }

  Future<String> get deviceId async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDeviceId) ?? 'esp32_01';
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyToken) ?? '';
    return {
      'Authorization': 'Bearer $token',
      'Content-Type':  'application/json',
    };
  }

  // ── internal helpers ──────────────────────────────────────────────────────

  Future<dynamic> _get(String path, {Map<String, String>? params}) async {
    final base    = await baseUrl;
    final headers = await _headers;
    final uri = Uri.parse('$base$path')
        .replace(queryParameters: params);
    final resp = await http.get(uri, headers: headers)
        .timeout(const Duration(seconds: 90));
    _assertOk(resp);
    return jsonDecode(resp.body);
  }

  Future<dynamic> _post(String path, {Map<String, dynamic>? body}) async {
    final base    = await baseUrl;
    final headers = await _headers;
    final resp = await http.post(
      Uri.parse('$base$path'),
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    ).timeout(const Duration(seconds: 30));
    _assertOk(resp);
    return jsonDecode(resp.body);
  }

  Future<dynamic> _patch(String path, Map<String, dynamic> body) async {
    final base    = await baseUrl;
    final headers = await _headers;
    final resp = await http.patch(
      Uri.parse('$base$path'),
      headers: headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));
    _assertOk(resp);
    return jsonDecode(resp.body);
  }

  Future<dynamic> _delete(String path) async {
    final base    = await baseUrl;
    final headers = await _headers;
    final resp = await http.delete(
      Uri.parse('$base$path'),
      headers: headers,
    ).timeout(const Duration(seconds: 30));
    _assertOk(resp);
    return jsonDecode(resp.body);
  }

  void _assertOk(http.Response resp) {
    if (resp.statusCode >= 400) {
      String message = 'HTTP ${resp.statusCode}';
      try {
        final body = jsonDecode(resp.body) as Map;
        message = body['error']?.toString() ?? message;
      } catch (_) {}
      throw ApiException(resp.statusCode, message);
    }
  }

  // ── summary endpoints ─────────────────────────────────────────────────────

  /// Fetch aggregated LLM summary for [window] ('6h', 'day', or '24h').
  Future<Map<String, dynamic>> getWindowSummary({
    required String deviceId,
    required String window,
    bool refresh = false,
  }) async {
    final params = <String, String>{
      'device_id': deviceId,
      'window':    window,
      if (refresh) 'refresh': 'true',
    };
    final data = await _get('/summary/window', params: params);
    return data as Map<String, dynamic>;
  }

  /// Return which dates/hours have recordings (for date picker).
  Future<List<dynamic>> getSummaryAvailable({
    required String deviceId,
    String? date,
  }) async {
    final params = <String, String>{
      'device_id': deviceId,
      if (date != null) 'date': date,
    };
    return (await _get('/summary/available', params: params)) as List;
  }

  // ── reminders endpoints ───────────────────────────────────────────────────

  /// List user-created reminders. [status]: 'pending'|'resolved'|'snoozed'|'all'.
  Future<List<dynamic>> getReminders({
    required String deviceId,
    String status = 'pending',
  }) async {
    return (await _get('/reminders', params: {
      'device_id': deviceId,
      'status':    status,
    })) as List;
  }

  /// Create a new reminder, optionally linked to an intent.
  Future<Map<String, dynamic>> createReminder({
    required String deviceId,
    required String title,
    String? notes,
    String? scheduledTime,
    int?    intentId,
    String  repeatRule = 'none',
  }) async {
    final data = await _post('/reminders', body: {
      'device_id':   deviceId,
      'title':       title,
      if (notes != null)         'notes':          notes,
      if (scheduledTime != null) 'scheduled_time': scheduledTime,
      if (intentId != null)      'intent_id':      intentId,
      'repeat_rule': repeatRule,
    });
    return data as Map<String, dynamic>;
  }

  /// Update one or more fields on a reminder.
  Future<void> updateReminder(int id, Map<String, dynamic> fields) async {
    await _patch('/reminders/$id', fields);
  }

  /// Convenience: mark a reminder resolved.
  Future<void> resolveReminder(int id) async =>
      updateReminder(id, {'status': 'resolved'});

  /// Delete a reminder permanently.
  Future<void> deleteReminder(int id) async {
    await _delete('/reminders/$id');
  }

  // ── intents endpoints ─────────────────────────────────────────────────────

  Future<List<dynamic>> getIntents({
    required String deviceId,
    String? decision,
    String? intentType,
  }) async {
    return (await _get('/intents', params: {
      'device_id': deviceId,
      if (decision != null)   'decision': decision,
      if (intentType != null) 'type':     intentType,
    })) as List;
  }

  Future<void> updateIntentStatus(int id, String status) async {
    await _patch('/intents/$id/status', {'status': status});
  }

  // ── sally Q&A ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> askSally({
    required String deviceId,
    required String question,
  }) async {
    final data = await _post('/sally/ask', body: {
      'device_id': deviceId,
      'question':  question,
    });
    return data as Map<String, dynamic>;
  }
}

/// Thrown when the server returns an HTTP error response.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
