import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/camera_streaming_config.dart';

/// Credentials of a paired phone. The device token is a secret: it is kept
/// only in the Android Keystore backed secure storage.
class StoredCredentials {
  const StoredCredentials({
    required this.serverUrl,
    required this.cameraId,
    required this.cameraName,
    required this.slot,
    required this.deviceToken,
  });

  final Uri serverUrl;
  final String cameraId;
  final String cameraName;
  final int slot;
  final String deviceToken;

  StoredCredentials copyWith({String? cameraName, int? slot}) => StoredCredentials(
        serverUrl: serverUrl,
        cameraId: cameraId,
        cameraName: cameraName ?? this.cameraName,
        slot: slot ?? this.slot,
        deviceToken: deviceToken,
      );

  Map<String, Object?> toJson() => {
        'serverUrl': serverUrl.toString(),
        'cameraId': cameraId,
        'cameraName': cameraName,
        'slot': slot,
        'deviceToken': deviceToken,
      };

  static StoredCredentials? fromJson(Map<String, Object?> json) {
    final server = Uri.tryParse(json['serverUrl'] as String? ?? '');
    final cameraId = json['cameraId'];
    final token = json['deviceToken'];
    if (server == null || !server.hasScheme || cameraId is! String || token is! String || token.length < 20) {
      return null;
    }
    return StoredCredentials(
      serverUrl: server,
      cameraId: cameraId,
      cameraName: json['cameraName'] is String ? json['cameraName'] as String : cameraId,
      slot: json['slot'] is num ? (json['slot'] as num).toInt() : 0,
      deviceToken: token,
    );
  }
}

/// Key/value secure storage abstraction (fake in tests).
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecretStore implements SecretStore {
  FlutterSecretStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class CredentialStore {
  CredentialStore(this._store);

  static const _credentialsKey = 'pcrc.credentials.v1';
  static const _configKey = 'pcrc.streaming_config.v1';
  static const _testEndpointKey = 'pcrc.test_endpoint.v1';

  final SecretStore _store;

  Future<StoredCredentials?> load() async {
    final raw = await _store.read(_credentialsKey);
    if (raw == null) return null;
    try {
      return StoredCredentials.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  Future<void> save(StoredCredentials credentials) => _store.write(_credentialsKey, jsonEncode(credentials.toJson()));

  /// Last streaming configuration received from the control plane, so that a
  /// local START works even if the control plane is temporarily unreachable.
  Future<CameraStreamingConfig?> loadConfig() async {
    final raw = await _store.read(_configKey);
    if (raw == null) return null;
    try {
      return CameraStreamingConfig.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  Future<void> saveConfig(CameraStreamingConfig config) => _store.write(_configKey, jsonEncode(config.toJson()));

  Future<String?> loadTestEndpoint() => _store.read(_testEndpointKey);

  Future<void> saveTestEndpoint(String? url) async {
    if (url == null || url.trim().isEmpty) {
      await _store.delete(_testEndpointKey);
    } else {
      await _store.write(_testEndpointKey, url.trim());
    }
  }

  Future<void> clear() async {
    await _store.delete(_credentialsKey);
    await _store.delete(_configKey);
  }
}
