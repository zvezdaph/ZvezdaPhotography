import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/video_settings.dart';

/// Non secret preferences (secrets live in CredentialStore).
class AppPreferences {
  const AppPreferences({
    this.video = const VideoSettings(),
    this.autoFallback = true,
    this.keepScreenOn = true,
    this.lastServerUrl,
    this.deviceName,
  });

  final VideoSettings video;
  final bool autoFallback;
  final bool keepScreenOn;
  final String? lastServerUrl;
  final String? deviceName;

  AppPreferences copyWith({
    VideoSettings? video,
    bool? autoFallback,
    bool? keepScreenOn,
    String? lastServerUrl,
    String? deviceName,
  }) =>
      AppPreferences(
        video: video ?? this.video,
        autoFallback: autoFallback ?? this.autoFallback,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        lastServerUrl: lastServerUrl ?? this.lastServerUrl,
        deviceName: deviceName ?? this.deviceName,
      );
}

abstract class SettingsStore {
  Future<AppPreferences> load();
  Future<void> save(AppPreferences preferences);
}

class SharedPrefsSettingsStore implements SettingsStore {
  static const _key = 'pcrc.preferences.v1';

  @override
  Future<AppPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const AppPreferences();
    try {
      final json = (jsonDecode(raw) as Map).cast<String, Object?>();
      return AppPreferences(
        video: json['video'] is Map
            ? VideoSettings.fromJson((json['video'] as Map).cast<String, Object?>())
            : const VideoSettings(),
        autoFallback: json['autoFallback'] != false,
        keepScreenOn: json['keepScreenOn'] != false,
        lastServerUrl: json['lastServerUrl'] as String?,
        deviceName: json['deviceName'] as String?,
      );
    } catch (_) {
      return const AppPreferences();
    }
  }

  @override
  Future<void> save(AppPreferences p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'video': p.video.toJson(),
        'autoFallback': p.autoFallback,
        'keepScreenOn': p.keepScreenOn,
        'lastServerUrl': p.lastServerUrl,
        'deviceName': p.deviceName,
      }),
    );
  }
}

class MemorySettingsStore implements SettingsStore {
  AppPreferences value = const AppPreferences();
  @override
  Future<AppPreferences> load() async => value;
  @override
  Future<void> save(AppPreferences preferences) async => value = preferences;
}
