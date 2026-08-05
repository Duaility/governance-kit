#!/usr/bin/env bash
# Costs row schema (v6) + snapshot-sidecar plumbing for agent-token-accounting.
#
# Row schema — v6 (10 columns, issue #355):
#
#   | date | harness | session | model | input | cache-create | cache-read |
#     output | cost-usd | source |
#
# One row **per session per issue** — not per commit. A session's spend is not
# final at any commit, so a per-commit row could only ever be a snapshot of a
# moving number dressed up as a fact; and a session that touches an issue over
# twenty commits is one unit of spend, not twenty. The row is updated in place
# while the PR is open (receipts freeze only once they reach the trunk) and
# converges on the truth as later resolves land.
#
# - `date`    — the day this session first touched this issue. Never rewritten.
# - numbers   — the harness's own session-cumulative counters from the sidecar's
#               authoritative snapshot, or the literal `-` when nothing has
#               resolved yet.
# - `cost-usd`— the harness's own dollar figure verbatim, or `-`. The kit owns
#               no rate card and never prices: a blank beats an estimate,
#               because an estimate rendered to four decimals reads like a
#               measurement.
# - `source`  — provenance of the numbers: `harness-feed` (the harness pushed
#               them), `session-file` (an adapter read a harness-declared file),
#               `server` (an adapter queried the harness's local server),
#               `manual` (a human supplied them, labelled as such), or
#               `unresolved` (nothing has been measured yet).
#
# Legacy rows are recognised by cell count and structurally tolerated, never
# validated: 17 = v5, 16 = v4, 12 = v3. Validation lives in sibling
# `validate.sh`; the Markdown plumbing in sibling `receipt.sh` (source it
# first); identity + sidecar paths in sibling `runtime.sh`.

COSTS_SUBHEADING="### Costs"
COSTS_COLS_V6=10
COSTS_HEADER="| date | harness | session | model | input | cache-create | cache-read | output | cost-usd | source |"
COSTS_SEPARATOR="| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"
# The closed set of provenance labels a v6 row may carry.
COSTS_SOURCES=" harness-feed session-file server manual unresolved "

# costs_rows <receipt>  → the receipt's Costs data rows, raw.
costs_rows() {
    receipt_rows "$1" "$COSTS_SUBHEADING"
}

# costs_row <receipt> <harness> <session>
#   The raw v6 row line for that identity, or nothing. Several hits print
#   several lines (the validator treats that as a violation).
costs_row() {
    costs_rows "$1" | COSTS_H="$2" COSTS_S="$3" awk "
$_RECEIPT_AWK_REGION"'
BEGIN { h = ENVIRON["COSTS_H"]; s = ENVIRON["COSTS_S"] }
{
    m = ncells($0, c)
    if (is_skip_row(c, m, "date")) { next }
    if (m != 10) { next }
    if (c[2] == h && c[3] == s) { print $0 }
}
'
}

# costs_session_keys <receipt>  → `<harness>\t<session>` for every v6 row.
costs_session_keys() {
    costs_rows "$1" | awk "
$_RECEIPT_AWK_REGION"'
{
    m = ncells($0, c)
    if (is_skip_row(c, m, "date")) { next }
    if (m != 10) { next }
    print c[2] "\t" c[3]
}
'
}

# _costs_replace_row <receipt> <harness> <session> <row-line>
#   Overwrite the matching v6 row inside the Costs sub-table, in place.
_costs_replace_row() {
    local file="$1" tmp
    tmp="$file.gk-tmp.$$"
    COSTS_H="$2" COSTS_S="$3" COSTS_ROW="$4" awk "
$_RECEIPT_AWK_REGION"'
BEGIN {
    h = ENVIRON["COSTS_H"]; s = ENVIRON["COSTS_S"]; row = ENVIRON["COSTS_ROW"]
    in_acc = 0; in_sub = 0
}
{ t = trim($0) }
t == "## Accounting" { in_acc = 1; in_sub = 0; print; next }
in_acc && ($0 ~ /^## / || $0 ~ /^# /) { in_acc = 0; in_sub = 0; print; next }
in_acc && $0 ~ /^### / { in_sub = (t == "### Costs") ? 1 : 0; print; next }
{
    if (in_acc && in_sub && t ~ /^\|/) {
        m = ncells($0, c)
        if (!is_skip_row(c, m, "date") && m == 10 && c[2] == h && c[3] == s) {
            print row
            next
        }
    }
    print
}
' "$file" > "$tmp" && mv "$tmp" "$file"
}

# costs_upsert_row <receipt> <harness> <session> <model> \
#                  <input> <cache-create> <cache-read> <output> \
#                  <cost-usd> <source>
#   Ensure exactly one v6 row exists for <harness>+<session> and carry the
#   given cells into it. An existing row keeps its original `date` — the day
#   the session first touched this issue is a fact about the past, not a field
#   to refresh. Empty inputs degrade to `-`, never to a zero: a zero is a
#   measurement, `-` is the absence of one.
costs_upsert_row() {
    local receipt="$1" harness="$2" session="$3" model="${4:--}"
    local inp="${5:--}" cc="${6:--}" cr="${7:--}" out="${8:--}"
    local cost="${9:--}" src="${10:-unresolved}"
    local existing first day row

    [ -n "$model" ] || model="-"
    [ -n "$inp" ] || inp="-"
    [ -n "$cc" ] || cc="-"
    [ -n "$cr" ] || cr="-"
    [ -n "$out" ] || out="-"
    [ -n "$cost" ] || cost="-"
    [ -n "$src" ] || src="unresolved"

    existing="$(costs_row "$receipt" "$harness" "$session" | head -n 1)"
    day=""
    if [ -n "$existing" ]; then
        first="$(printf '%s\n' "$existing" | awk -F'[|]' '
{ v = $2; sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print v }')"
        case "$first" in
            [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) day="$first" ;;
        esac
    fi
    [ -n "$day" ] || day="$(date +%Y-%m-%d)"

    row="| $day | $harness | $session | $model | $inp | $cc | $cr | $out | $cost | $src |"
    if [ -n "$existing" ]; then
        _costs_replace_row "$receipt" "$harness" "$session" "$row"
    else
        receipt_insert_row "$receipt" "$COSTS_SUBHEADING" \
            "$COSTS_HEADER" "$COSTS_SEPARATOR" "$row"
    fi
}

# costs_row_snapshot <receipt> <harness> <session>
#   The row's measurement cells in snapshot order —
#   `<input> <cc> <cr> <output> <model> <cost> <source>` — so a receipt row can
#   be compared directly against `costs_fold_snapshot`. Nothing when absent.
costs_row_snapshot() {
    costs_row "$1" "$2" "$3" | head -n 1 | awk -F'[|]' '
NF == 12 {
    for (i = 1; i <= NF; i++) { sub(/^[ \t]+/, "", $i); sub(/[ \t]+$/, "", $i) }
    print $6 " " $7 " " $8 " " $9 " " $5 " " $10 " " $11
}
'
}

# ── Snapshot sidecar ───────────────────────────────────────────────────────
# `v1 <epoch> <input> <cache_create> <cache_read> <output> <model> <cost|-> <source>`
# Append-only, one file per session. Writers are off the commit path (adapter
# `emit` and adapter `resolve`); the commit path only ever reads.

# costs_snapshot_append <sidecar-file> <input> <cc> <cr> <output> <model> <cost> <source>
#   Append one snapshot. A snapshot identical to the sidecar's last line
#   (ignoring the timestamp) is dropped, so a resolve sweep on every commit
#   does not grow the file without adding information.
costs_snapshot_append() {
    local file="$1" inp="$2" cc="$3" cr="$4" out="$5"
    local model="$6" cost="$7" src="$8"
    local body last

    [ -n "$model" ] || model="-"
    [ -n "$cost" ] || cost="-"
    body="$inp $cc $cr $out $model $cost $src"
    if [ -f "$file" ]; then
        last="$(tail -n 1 "$file" | cut -d' ' -f3-)"
        [ "$last" = "$body" ] && return 0
    fi
    mkdir -p "$(dirname "$file")"
    printf 'v1 %s %s\n' "$(date +%s)" "$body" >> "$file"
}

# costs_fold_snapshot <sidecar-file>
#   The authoritative snapshot: `<input> <cc> <cr> <output> <model> <cost> <source>`,
#   or nothing when the sidecar is absent/empty.
#
#   Fold rule (spec'd so the directive and the adapters agree): take the latest
#   snapshot overall, EXCEPT that a `session-file` / `server` reading wins any
#   tie or later position, because those carry full token detail while a
#   `harness-feed` push may legitimately carry only cost and identity. Stated
#   the other way round: prefer the latest file/server snapshot over a
#   harness-feed one whenever it is not older.
costs_fold_snapshot() {
    [ -f "$1" ] || return 0
    awk '
$1 == "v1" && NF == 9 {
    ep = $2 + 0
    rec = $3 " " $4 " " $5 " " $6 " " $7 " " $8 " " $9
    last_ep = ep; last = rec; have_last = 1
    if ($9 == "session-file" || $9 == "server") { f_ep = ep; f = rec; have_f = 1 }
}
END {
    if (have_f && f_ep >= last_ep) { print f; exit }
    if (have_last) { print last }
}
' "$1"
}
