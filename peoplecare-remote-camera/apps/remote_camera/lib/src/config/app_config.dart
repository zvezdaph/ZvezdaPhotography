/// Build-time configuration.
///
/// The default control plane URL can be baked into the APK with
/// `--dart-define=CONTROL_PLANE_URL=https://your-worker.workers.dev`
/// (see scripts/build_android.sh). It can always be changed in the pairing screen.
class AppConfig {
  static const String defaultControlPlaneUrl = String.fromEnvironment('CONTROL_PLANE_URL');

  /// Debug builds may talk to a local `wrangler dev` over plain HTTP.
  static const bool allowInsecureControlPlane = bool.fromEnvironment('ALLOW_INSECURE_CONTROL_PLANE');

  static const String appName = 'PeopleCare Remote Camera';
  static const int protocolVersion = 1;
}
