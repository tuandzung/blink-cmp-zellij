# Async parallel completions with TTL cache

The original `get_completions` used synchronous `vim.system():wait()` calls, blocking the Neovim event loop for N+1 sequential subprocess spawns per completion request. In all-panes mode with 4 panes, each keystroke caused ~80ms of blocking, and blink.cmp's request queuing (no cancellation opt-in from the source) amplified this into a staircase of blocking chains during fast typing. We're replacing this with callback-based async `vim.system` calls that fire all `dump-screen` commands in parallel, return a cancellation function so blink.cmp can abort stale requests (killing in-flight subprocesses), and layer a configurable TTL cache on top to avoid redundant subprocess spawns for unchanged pane content.

## Considered Options

- **Synchronous with debounce** — add a timer to throttle `get_completions`. Rejected: doesn't solve the blocking problem, just reduces frequency.
- **Async with coroutines** — wrap subprocess calls in `coroutine.wrap`. Rejected: coroutines serialize waits, defeating parallelism.
- **Async callbacks (chosen)** — fire all subprocesses concurrently, collect results via a pending counter, return cancel fn. Latency drops from O(N) sequential to O(1) parallel.

## Consequences

- The `triggered_only` textEdit path captures context at call time; if cursor moves before callback fires, the range may be stale. Acceptable because `triggered_only` usage is rare and blink.cmp handles range adjustment.
- Cache is purely time-based (no pane structure fingerprint). Pane layout changes may take up to `cache_ttl` ms to reflect. Acceptable because pane changes are rare during active typing.
- Both `all_panes` modes share a uniform async code path. Single-pane mode gains cancellation support it didn't have.
