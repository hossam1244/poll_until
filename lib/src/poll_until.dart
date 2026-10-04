/// The polling engine. Pure Dart; time is injected.
library;

/// Pauses between attempts. Inject `Future.delayed` in production and a
/// no-op recorder in tests.
typedef Sleeper = Future<void> Function(Duration delay);

/// Supplies "now" so deadlines are testable.
typedef Clock = DateTime Function();

class PollTimeout implements Exception {
  PollTimeout(this.attempts, this.elapsed);

  final int attempts;
  final Duration elapsed;

  @override
  String toString() =>
      'PollTimeout: condition not met after $attempts attempt(s) in ${elapsed.inMilliseconds}ms';
}

class PollCancelled implements Exception {
  @override
  String toString() => 'PollCancelled: polling was cancelled by the caller';
}

/// The result of a completed poll.
class PollResult<T> {
  PollResult(
      {required this.value, required this.attempts, required this.elapsed});

  /// The final value of the polled function.
  final T value;

  /// How many attempts were made, including the successful one.
  final int attempts;

  /// Total wall-clock time from first attempt to completion.
  final Duration elapsed;
}

/// Polls [poll] until [isDone] returns true for its value.
///
/// ```dart
/// final deployment = await pollUntil(
///   () => api.deploymentStatus(id),
///   isDone: (status) => status.state != 'pending',
///   initialDelay: const Duration(seconds: 1),
///   backoff: PollBackoff.exponential(initial: Duration(seconds: 1), factor: 2),
///   timeout: const Duration(minutes: 5),
/// );
/// ```
///
/// * [initialDelay] — wait before the **first** attempt (default: none).
/// * [backoff] — the delay between attempts (default: none).
/// * [timeout] — give up with [PollTimeout] after this deadline
///   (default: no deadline).
/// * [sleep]/[clock] — injectable time; defaults use real `Future.delayed`
///   and `DateTime.now`.
Future<PollResult<T>> pollUntil<T>(
  Future<T> Function() poll, {
  required bool Function(T value) isDone,
  Duration initialDelay = Duration.zero,
  PollBackoff? backoff,
  Duration? timeout,
  Sleeper? sleep,
  Clock? clock,
}) async {
  final sleeper = sleep ?? (delay) => Future<void>.delayed(delay);
  final now = clock ?? DateTime.now;
  final startedAt = now();
  var attempts = 0;

  if (initialDelay > Duration.zero) {
    await sleeper(initialDelay);
  }

  while (true) {
    if (timeout != null && now().difference(startedAt) >= timeout) {
      throw PollTimeout(attempts, now().difference(startedAt));
    }

    attempts++;
    final value = await poll();
    if (isDone(value)) {
      return PollResult(
        value: value,
        attempts: attempts,
        elapsed: now().difference(startedAt),
      );
    }

    final nextDelay = backoff?.delayForAttempt(attempts) ?? Duration.zero;
    if (nextDelay > Duration.zero) {
      await sleeper(nextDelay);
    }
  }
}

/// Delay strategy between attempts.
abstract class PollBackoff {
  /// Delay before the given attempt number (1-based, the attempt about to
  /// run after this delay).
  Duration delayForAttempt(int attempt);

  /// Constant delay between attempts.
  const factory PollBackoff.fixed(Duration delay) = FixedBackoff;

  /// Delay that grows by [factor] each attempt, capped at [max].
  const factory PollBackoff.exponential({
    required Duration initial,
    double factor,
    Duration? max,
  }) = ExponentialBackoff;
}

class FixedBackoff implements PollBackoff {
  const FixedBackoff(this.delay);

  final Duration delay;

  @override
  Duration delayForAttempt(int attempt) => delay;
}

class ExponentialBackoff implements PollBackoff {
  const ExponentialBackoff({
    required this.initial,
    this.factor = 2,
    this.max,
  });

  final Duration initial;
  final double factor;
  final Duration? max;

  @override
  Duration delayForAttempt(int attempt) {
    var current = initial;
    for (var i = 1; i < attempt; i++) {
      current = Duration(
        microseconds: (current.inMicroseconds * factor).round(),
      );
      final cap = max;
      if (cap != null && current > cap) {
        return cap;
      }
    }
    final cap = max;
    if (cap != null && current > cap) {
      return cap;
    }
    return current;
  }
}

/// Cancellation token for cooperative cancellation.
class PollCancellationToken {
  var _cancelled = false;
  String? _reason;

  bool get isCancelled => _cancelled;
  String? get reason => _reason;

  void cancel([String? reason]) {
    _cancelled = true;
    _reason = reason ?? 'cancelled';
  }
}

/// Like [pollUntil], but checks [token] between every attempt and throws
/// [PollCancelled] as soon as the caller cancels.
Future<PollResult<T>> pollUntilCancellable<T>(
  Future<T> Function() poll, {
  required bool Function(T value) isDone,
  required PollCancellationToken token,
  Duration initialDelay = Duration.zero,
  PollBackoff? backoff,
  Duration? timeout,
  Sleeper? sleep,
  Clock? clock,
}) async {
  final sleeper = sleep ?? (delay) => Future<void>.delayed(delay);
  final now = clock ?? DateTime.now;
  final startedAt = now();
  var attempts = 0;

  if (initialDelay > Duration.zero) {
    await sleeper(initialDelay);
  }

  while (true) {
    if (token.isCancelled) {
      throw PollCancelled();
    }
    if (timeout != null && now().difference(startedAt) >= timeout) {
      throw PollTimeout(attempts, now().difference(startedAt));
    }

    attempts++;
    final value = await poll();
    if (isDone(value)) {
      return PollResult(
        value: value,
        attempts: attempts,
        elapsed: now().difference(startedAt),
      );
    }

    final nextDelay = backoff?.delayForAttempt(attempts) ?? Duration.zero;
    if (nextDelay > Duration.zero) {
      await sleeper(nextDelay);
    }
  }
}
