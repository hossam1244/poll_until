# poll_until

**Poll an async function until a condition is met** — Dart & Flutter.

Fixed or exponential backoff between attempts, a deadline, cooperative
cancellation, and **deterministic tests** via injectable sleep/clock.

[![CI](https://github.com/hossam1244/poll_until/actions/workflows/ci.yml/badge.svg)](https://github.com/hossam1244/poll_until/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Why

Waiting for eventual consistency is everywhere: deployment status, job
completion, OTP email arrival, an ML inference result. The ad-hoc versions
(`while (!done) { await Future.delayed(...); }`) miss the same three things:
a **deadline**, **growing backoff** so you don't hammer the endpoint, and
**cancellation** when the user navigates away. And they're miserable to test
because real time is baked in.

```dart
final deployment = await pollUntil(
  () => api.deploymentStatus(id),
  isDone: (status) => status.state != 'pending',
  backoff: PollBackoff.exponential(initial: Duration(seconds: 1), factor: 2),
  timeout: Duration(minutes: 5),
);
```

Cancellable variant for screens the user can leave:

```dart
final token = PollCancellationToken();
subscription = routeObserver.onLeave.listen((_) => token.cancel());

final result = await pollUntilCancellable(
  () => api.invoiceState(id),
  isDone: (state) => state.isFinal,
  token: token,
  backoff: PollBackoff.fixed(Duration(seconds: 2)),
);
```

Time is injected (`sleep`, `clock`), so tests run instantly and assert the
exact delays used — see the suite: 9 tests covering first-hit success,
deadline diagnostics, immediate cancellation, fixed and capped-exponential
backoff schedules, initial delay, and elapsed reporting.

```bash
dart test
```

## License

[MIT](LICENSE)
