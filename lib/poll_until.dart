/// Poll an async function until a condition is met.
///
/// Fixed or exponential backoff between attempts, a deadline, and
/// cooperative cancellation — deterministic in tests via an injectable
/// sleeper and clock.
library;

export 'src/poll_until.dart';
