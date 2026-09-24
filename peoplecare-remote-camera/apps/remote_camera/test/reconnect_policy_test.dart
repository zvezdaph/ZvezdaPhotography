import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_camera/src/control/reconnect_policy.dart';

class _FixedRandom implements Random {
  _FixedRandom(this.value);
  final double value;
  @override
  double nextDouble() => value;
  @override
  bool nextBool() => false;
  @override
  int nextInt(int max) => 0;
}

void main() {
  group('reconnect policy', () {
    test('exponential backoff capped at 30 s', () {
      final policy = ReconnectPolicy(random: _FixedRandom(0));
      final delays = List.generate(8, (_) => policy.nextDelay().inMilliseconds);
      expect(delays, [1000, 2000, 4000, 8000, 16000, 30000, 30000, 30000]);
      expect(policy.attempts, 8);
    });

    test('jitter keeps the delay in [delay/2, delay]', () {
      final low = ReconnectPolicy(random: _FixedRandom(0.999999));
      expect(low.nextDelay().inMilliseconds, 500);
      final policy = ReconnectPolicy();
      for (var i = 0; i < 50; i++) {
        final attempt = policy.attempts;
        final base = min(30000, 1000 * pow(2, attempt)).toInt();
        final d = policy.nextDelay().inMilliseconds;
        expect(d, inInclusiveRange(base ~/ 2, base));
      }
    });

    test('reset after a successful connection', () {
      final policy = ReconnectPolicy(random: _FixedRandom(0));
      policy.nextDelay();
      policy.nextDelay();
      policy.reset();
      expect(policy.nextDelay().inMilliseconds, 1000);
    });
  });
}
