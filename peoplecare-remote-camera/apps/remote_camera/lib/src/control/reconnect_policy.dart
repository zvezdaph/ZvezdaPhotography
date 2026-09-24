import 'dart:math';

/// Exponential backoff with jitter (1 s, x2, max 30 s, 50% jitter).
/// Same policy as the native SRT reconnection and the Control Room socket.
class ReconnectPolicy {
  ReconnectPolicy({
    this.initial = const Duration(seconds: 1),
    this.max = const Duration(seconds: 30),
    this.multiplier = 2.0,
    this.jitter = 0.5,
    Random? random,
  }) : _random = random ?? Random();

  final Duration initial;
  final Duration max;
  final double multiplier;
  final double jitter;
  final Random _random;
  int _attempt = 0;

  int get attempts => _attempt;

  Duration nextDelay() {
    final baseMs = min(max.inMilliseconds.toDouble(), initial.inMilliseconds * pow(multiplier, _attempt));
    _attempt++;
    final spread = baseMs * jitter * _random.nextDouble();
    return Duration(milliseconds: (baseMs - spread).round());
  }

  void reset() => _attempt = 0;
}
