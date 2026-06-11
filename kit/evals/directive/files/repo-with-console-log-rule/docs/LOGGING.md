# Logging

We use pino for structured logging. See the `no-console-log` governance rule for the reason we block `console.log` in source files — if you ever need a printf debug, waive it inline with `// governance: allow-no-console-log <TICKET>` and remove the waiver before merging.
