import 'dart:convert';
import 'dart:io';

import 'app_config.dart';
import 'intent_record.dart';

class SallyApiException implements Exception {
  SallyApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SallyApiClient {
  SallyApiClient({HttpClient? httpClient}) : _injectedClient = httpClient;

  final HttpClient? _injectedClient;

  // Created lazily (only on the first real request), so the app also runs on
  // Flutter web in demo mode, where dart:io's HttpClient doesn't exist.
  late final HttpClient _httpClient = (_injectedClient ?? HttpClient())
    ..connectionTimeout = const Duration(seconds: 10);

  Future<List<IntentRecord>> fetchIntents({
    String deviceId = sallyDeviceId,
    bool includeTranscript = true,
    bool includeSummary = true,
  }) async {
    if (!isSallyApiConfigured) {
      throw SallyApiException(
        'Set SALLY_API_BASE_URL before loading Pi data.',
      );
    }

    final Uri uri = Uri.parse('$sallyApiBaseUrl/intents').replace(
      queryParameters: <String, String>{
        'device_id': deviceId,
        if (includeTranscript) 'include_transcript': 'true',
        if (includeSummary) 'include_summary': 'true',
      },
    );

    final HttpClientRequest request =
        await _httpClient.getUrl(uri).timeout(const Duration(seconds: 10));
    if (sallyApiToken.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $sallyApiToken');
    }
    final HttpClientResponse response =
        await request.close().timeout(const Duration(seconds: 10));
    final String responseBody =
        await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SallyApiException(
        _extractError(responseBody) ??
            'Server returned ${response.statusCode}.',
      );
    }

    final dynamic decoded = jsonDecode(responseBody);
    if (decoded is! List) {
      throw SallyApiException('Unexpected response from /intents.');
    }

    return decoded
        .whereType<Map>()
        .map((item) => IntentRecord.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<String> askSally({
    required String question,
    String deviceId = sallyDeviceId,
    List<Map<String, String>> history = const [],
  }) async {
    if (!isSallyApiConfigured) {
      throw SallyApiException('Set SALLY_API_BASE_URL before asking Sally.');
    }

    final Uri uri = Uri.parse('$sallyApiBaseUrl/sally/ask');
    final HttpClientRequest request =
        await _httpClient.postUrl(uri).timeout(const Duration(seconds: 30));
    request.headers.set('Content-Type', 'application/json');
    if (sallyApiToken.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $sallyApiToken');
    }
    request.write(jsonEncode({
      'question': question,
      'device_id': deviceId,
      'history': history,
    }));
    final HttpClientResponse response =
        await request.close().timeout(const Duration(seconds: 30));
    final String responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SallyApiException(
        _extractError(responseBody) ?? 'Server returned ${response.statusCode}.',
      );
    }

    final dynamic decoded = jsonDecode(responseBody);
    if (decoded is Map && decoded['answer'] is String) {
      return decoded['answer'] as String;
    }
    throw SallyApiException('Unexpected response from /sally/ask.');
  }

  Future<String> askPatient({
    required String question,
    String deviceId = sallyDeviceId,
    List<Map<String, String>> history = const [],
  }) async {
    if (kDemoMode) {
      await Future.delayed(const Duration(milliseconds: 1200)); // shows the typing dots
      return 'This is a demo answer, the server is not connected. '
          'Today you talked with your partner about the crib delay, called the insurance '
          'company about the ultrasound claim, and planned the baby shower with your sister.';
    }
    if (!isSallyApiConfigured) {
      throw SallyApiException('Set SALLY_API_BASE_URL before asking Sally.');
    }

    final Uri uri = Uri.parse('$sallyApiBaseUrl/caregiver/ask');
    final HttpClientRequest request =
        await _httpClient.postUrl(uri).timeout(const Duration(seconds: 30));
    request.headers.set('Content-Type', 'application/json');
    if (sallyApiToken.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $sallyApiToken');
    }
    request.write(jsonEncode({
      'question': question,
      'device_id': deviceId,
      'history': history,
    }));
    final HttpClientResponse response =
        await request.close().timeout(const Duration(seconds: 30));
    final String responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SallyApiException(
        _extractError(responseBody) ?? 'Server returned ${response.statusCode}.',
      );
    }

    final dynamic decoded = jsonDecode(responseBody);
    if (decoded is Map && decoded['answer'] is String) {
      return decoded['answer'] as String;
    }
    throw SallyApiException('Unexpected response from /caregiver/ask.');
  }

  String? _extractError(String responseBody) {
    try {
      final dynamic decoded = jsonDecode(responseBody);
      if (decoded is Map && decoded['error'] is String) {
        final message = (decoded['error'] as String).trim();
        if (message.isNotEmpty) {
          return message;
        }
      }
    } catch (_) {
      final message = responseBody.trim();
      if (message.isNotEmpty) {
        return message;
      }
    }
    return null;
  }
}
