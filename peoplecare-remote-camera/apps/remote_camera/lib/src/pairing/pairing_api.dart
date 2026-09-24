import 'dart:convert';

import 'package:http/http.dart' as http;

class PairingException implements Exception {
  PairingException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

class PairingTicket {
  const PairingTicket({
    required this.pairingId,
    required this.code,
    required this.pollToken,
    required this.expiresAt,
    required this.pollInterval,
  });

  final String pairingId;
  final String code;
  final String pollToken;
  final DateTime expiresAt;
  final Duration pollInterval;
}

sealed class PollResult {
  const PollResult();
}

class PollPending extends PollResult {
  const PollPending();
}

class PollExpired extends PollResult {
  const PollExpired();
}

class PollPaired extends PollResult {
  const PollPaired({required this.cameraId, required this.cameraName, required this.slot, required this.deviceToken});
  final String cameraId;
  final String cameraName;
  final int slot;
  final String deviceToken;
}

/// HTTPS client of the pairing endpoints of the control plane.
class PairingApi {
  PairingApi(this.serverUrl, {http.Client? client, this.allowInsecure = false}) : _client = client ?? http.Client();

  final Uri serverUrl;
  final bool allowInsecure;
  final http.Client _client;

  /// Validates and normalizes the server URL typed by the operator.
  static Uri normalizeServerUrl(String input, {bool allowInsecure = false}) {
    var text = input.trim();
    if (text.isEmpty) throw PairingException('invalid_server', 'Inserisci l\'indirizzo della regia');
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) throw PairingException('invalid_server', 'Indirizzo della regia non valido');
    if (uri.scheme != 'https' && !(allowInsecure && uri.scheme == 'http')) {
      throw PairingException('insecure_server', 'La regia deve usare HTTPS');
    }
    return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null);
  }

  Future<Map<String, Object?>> _post(String path, Map<String, Object?> body, {String? bearer}) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            serverUrl.replace(path: path),
            headers: {
              'Content-Type': 'application/json',
              if (bearer != null) 'Authorization': 'Bearer $bearer',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw PairingException('network', 'Regia non raggiungibile: controlla la rete e l\'indirizzo');
    }
    Map<String, Object?> json;
    try {
      json = (jsonDecode(response.body) as Map).cast<String, Object?>();
    } catch (_) {
      throw PairingException('bad_response', 'Risposta non valida dalla regia (HTTP ${response.statusCode})');
    }
    if (response.statusCode >= 400) {
      final error = json['error'] is Map ? (json['error'] as Map).cast<String, Object?>() : const <String, Object?>{};
      throw PairingException(
        error['code'] as String? ?? 'http_${response.statusCode}',
        error['message'] as String? ?? 'Errore HTTP ${response.statusCode}',
      );
    }
    return json;
  }

  Future<PairingTicket> start({required String deviceName, String? model, String? appVersion}) async {
    final json = await _post('/api/pair/start', {
      'deviceName': deviceName,
      'model': model,
      'appVersion': appVersion,
      'platform': 'android',
    });
    final pairingId = json['pairingId'];
    final code = json['code'];
    final pollToken = json['pollToken'];
    final expiresAt = json['expiresAt'];
    if (pairingId is! String || code is! String || pollToken is! String || expiresAt is! num) {
      throw PairingException('bad_response', 'Risposta di associazione incompleta');
    }
    final interval = json['pollIntervalMs'] is num ? (json['pollIntervalMs'] as num).toInt() : 3000;
    return PairingTicket(
      pairingId: pairingId,
      code: code,
      pollToken: pollToken,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt.toInt()),
      pollInterval: Duration(milliseconds: interval.clamp(1000, 10000)),
    );
  }

  Future<PollResult> poll(PairingTicket ticket) async {
    final json = await _post('/api/pair/poll', {'pairingId': ticket.pairingId}, bearer: ticket.pollToken);
    switch (json['status']) {
      case 'pending':
        return const PollPending();
      case 'paired':
        final cameraId = json['cameraId'];
        final token = json['deviceToken'];
        if (cameraId is! String || token is! String) throw PairingException('bad_response', 'Risposta incompleta');
        return PollPaired(
          cameraId: cameraId,
          cameraName: json['cameraName'] is String ? json['cameraName'] as String : cameraId,
          slot: json['slot'] is num ? (json['slot'] as num).toInt() : 0,
          deviceToken: token,
        );
      default:
        return const PollExpired();
    }
  }

  void close() => _client.close();
}

/// Content of the pairing QR code read by the Control Room webcam scanner.
String pairingQrPayload(String code, Uri server) => 'PCRC:1:$code:${server.host}';
