# 2026-04-23 — Complete Codex Agent Accounting

## Goal

Make Codex-authored commits produce complete `COSTS.md` rows with the same fidelity as Claude Code: reliable transcript discovery, model capture, cached-token split, and priced `cost-usd` values.

## Steps

1. Update the Codex runtime reader to find nested rollout transcripts by `CODEX_THREAD_ID`, including archived sessions.
2. Parse Codex Desktop `token_count.info.total_token_usage` records as cumulative usage and split OpenAI cached input out of base input.
3. Capture Codex model ids from current transcript metadata and add GPT-5.4 family rates to the pricing table.
4. Verify the reader against the current Codex Desktop transcript and run the governance suite.
