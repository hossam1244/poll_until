import 'package:poll_until/poll_until.dart';
import 'package:test/test.dart';

void main() {
  // Injected time: records sleeps, advances a fake clock by the slept amount.
  late List<Duration> sleeps;
  late DateTime fakeNow;

  Future<void> recorder(Duration delay) async {
    sleeps.add(delay);
    fakeNow = fakeNow.add(delay);
  }

  setUp(() {
    sleeps = [];
    fakeNow = DateTime(2026, 1, 1);
  });

  test('returns the first value that satisfies the condition', () async {
    final values = ['pending', 'pending', 'done'];

    final result = await pollUntil(
      () async => values.removeAt(0),
      isDone: (value) => value == 'done',
      clock: () => fakeNow,
    );

    expect(result.value, 'done');
    expect(result.attempts, 3);
  });

  test('timeout throws PollTimeout with diagnostics', () async {
    await expectLater(
      pollUntil(
        () async => 'pending',
        isDone: (value) => false,
        timeout: const Duration(seconds: 10),
        clock: () => fakeNow,
        // Keep the loop bounded even without backoff: exponential delays
        // advance the fake clock past the deadline.
        backoff: PollBackoff.exponential(initial: Duration(seconds: 1)),
        sleep: recorder,
      ),
      throwsA(isA<PollTimeout>()),
    );
  });

  test('cancellation stops polling immediately', () async {
    final token = PollCancellationToken();
    var calls = 0;

    await expectLater(
      pollUntilCancellable(
        () async {
          calls++;
          if (calls == 2) token.cancel('user navigated away');
          return 'pending';
        },
        isDone: (value) => false,
        token: token,
        clock: () => fakeNow,
      ),
      throwsA(isA<PollCancelled>()),
    );

    expect(calls, 2,
        reason: 'cancel fired during attempt 2; checked before attempt 3');
  });

  test('fixed backoff sleeps the same delay between attempts', () async {
    final values = ['a', 'b', 'c'];

    await pollUntil(
      () async => values.removeAt(0),
      isDone: (value) => value == 'c',
      backoff: PollBackoff.fixed(const Duration(seconds: 2)),
      sleep: recorder,
      clock: () => fakeNow,
    );

    expect(sleeps, [Duration(seconds: 2), Duration(seconds: 2)]);
  });

  test('exponential backoff grows by factor and caps', () async {
    final backoff = PollBackoff.exponential(
      initial: const Duration(seconds: 1),
      factor: 2,
      max: const Duration(seconds: 5),
    );

    expect(backoff.delayForAttempt(1), const Duration(seconds: 1));
    expect(backoff.delayForAttempt(2), const Duration(seconds: 2));
    expect(backoff.delayForAttempt(3), const Duration(seconds: 4));
    expect(backoff.delayForAttempt(4), const Duration(seconds: 5),
        reason: 'capped');
    expect(backoff.delayForAttempt(50), const Duration(seconds: 5));
  });

  test('initial delay is applied before the first attempt', () async {
    var calls = 0;

    await pollUntil(
      () async => ++calls,
      isDone: (value) => value == 1,
      initialDelay: const Duration(milliseconds: 500),
      sleep: recorder,
      clock: () => fakeNow,
    );

    expect(sleeps, [Duration(milliseconds: 500)]);
    expect(calls, 1);
  });

  test('satisfied on the first attempt with no configured delays', () async {
    final result = await pollUntil(
      () async => 42,
      isDone: (value) => value == 42,
      clock: () => fakeNow,
    );

    expect(result.attempts, 1);
    expect(sleeps, isEmpty);
  });

  test('result reports elapsed time from the injected clock', () async {
    final result = await pollUntil(
      () async => 'pending',
      isDone: (value) => true,
      initialDelay: const Duration(seconds: 3),
      sleep: recorder,
      clock: () => fakeNow,
    );

    expect(result.elapsed, const Duration(seconds: 3));
  });

  test('PollTimeout message includes attempts and elapsed', () async {
    final timeout = PollTimeout(4, const Duration(seconds: 9));
    expect(timeout.toString(), contains('4'));
    expect(timeout.toString(), contains('9000'));
  });
}
