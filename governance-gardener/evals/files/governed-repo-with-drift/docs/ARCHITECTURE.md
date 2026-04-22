<!-- last-verified: 2024-01-01 -->
<!-- gardener-watches: src/server.ts, src/db.ts -->

# Architecture

The server in `src/server.ts` handles HTTP requests, and `src/db.ts` wraps a sqlite connection pool. Both modules are the source of truth for this document — when their shape changes, this doc needs a refresh.
