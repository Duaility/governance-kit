#!/usr/bin/env bash
# Cost-row schema + append/query helpers for agent-token-accounting.
#
# Row schema — v5 (17 columns, issue #355):
#
#   | cost-key | agent | session | issue | model | input | cache-create |
#     cache-read | output | new-work | cost-usd | cum-input |
#     cum-cache-create | cum-cache-read | cum-output | source | note |
#
# v5 adds `source` (the runtime adapter that produced the row: `claude-code`,
# `codex`, `manual`) and redefines `cost-usd`: it is the figure the HARNESS
# reported, verbatim, or EMPTY when the harness reported none. The kit no
# longer prices anything — the rate card and its per-model schedule are gone
# (issue #355). A blank cost cell is the honest answer, and it never blocks a
# commit; an estimate would be a fabrication with four decimal places.
#
# The four `cum-*` columns remain the row's absolute transcript coordinates and
# the accounting source of truth; the delta columns are derived claims proved by
# reconciliation wherever a session's consecutive rows are co-visible.
#
# Legacy rows keep parsing by cell count: v4 = 16 columns (no `source`),
# v3 = 12 (no `cum-*`). Validation lives in sibling `validate.sh`; the Markdown
# plumbing in sibling `receipt.sh` (source it first).

COSTS_SUBHEADING="### Costs"
COSTS_COLS_V5=17
COSTS_COLS_V4=16
COSTS_COLS_V3=12
COSTS_HEADER="| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | source | note |"
COSTS_SEPARATOR="| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"

# costs_rows <receipt>  → the receipt's Costs data rows, raw.
costs_rows() {
    receipt_rows "$1" "$COSTS_SUBHEADING"
}

# costs_all_rows <receipts-dir>  → every receipt's Costs data rows, raw,
#   each prefixed with `<receipt-basename>\t`.
costs_all_rows() {
    local dir="$1" f base
    [ -d "$dir" ] || return 0
    for f in "$dir"/issue-*.md; do
        [ -f "$f" ] || continue
        base="$(basename "$f")"
        costs_rows "$f" | while IFS= read -r line; do
            printf '%s\t%s\n' "$base" "$line"
        done
    done
}

# costs_append_row <receipt> <cost-key> <agent> <session> <issue> <model> \
#                  <input> <cache-create> <cache-read> <output> \
#                  <cum-input> <cum-cache-create> <cum-cache-read> <cum-output> \
#                  <cost-usd> <source> <note>
#   Append one v5 row. `new-work` is recomputed here (input + cache_create +
#   output — cache_read is tracked but excluded, it is the same bytes re-read).
#   A `-` (or empty) <cost-usd> writes an empty cell: the harness reported no
#   dollar figure and the kit does not invent one.
costs_append_row() {
    local receipt="$1" key="$2" agent="$3" session="$4" issue="$5" model="$6"
    local inp="$7" cc="$8" cr="$9" out="${10}"
    local ci="${11}" ccc="${12}" ccr="${13}" co="${14}"
    local cost="${15}" source="${16}" note="${17}"
    local new_work row

    new_work=$(( inp + cc + out ))
    [ "$cost" = "-" ] && cost=""
    note="$(receipt_safe_cell "$note" 80)"

    row="| $key | $agent | $session | $issue | $model | $inp | $cc | $cr | $out"
    row="$row | $new_work | $cost | $ci | $ccc | $ccr | $co | $source | $note |"
    receipt_insert_row "$receipt" "$COSTS_SUBHEADING" \
        "$COSTS_HEADER" "$COSTS_SEPARATOR" "$row"
}

# costs_next_index <receipts-dir> <key-prefix>
#   1 + the number of existing rows whose cost-key starts with <key-prefix>.
#   Closes the same-second collision window for the opaque cost-key.
costs_next_index() {
    costs_all_rows "$1" | COSTS_PREFIX="$2" awk "
$_RECEIPT_AWK_REGION"'
BEGIN { pre = ENVIRON["COSTS_PREFIX"]; n = 0 }
{
    line = $0
    sub(/^[^\t]*\t/, "", line)
    m = ncells(line, c)
    if (is_skip_row(c, m, "cost-key")) { next }
    if (index(c[1], pre) == 1) { n++ }
}
END { print n + 1 }
'
}

# costs_find_cum <receipt> <cost-key>
#   `<session> <cum-input> <cum-cache-create> <cum-cache-read> <cum-output>`
#   for the named row, or nothing when the key is absent / not v4+. Multiple
#   hits print multiple lines (the caller treats that as a violation).
costs_find_cum() {
    costs_rows "$1" | COSTS_KEY="$2" awk "
$_RECEIPT_AWK_REGION"'
BEGIN { key = ENVIRON["COSTS_KEY"] }
{
    m = ncells($0, c)
    if (is_skip_row(c, m, "cost-key")) { next }
    if (c[1] != key) { next }
    if (m < 16) { print c[3] " - - - -"; next }
    print c[3] " " c[12] " " c[13] " " c[14] " " c[15]
}
'
}
