#!/usr/bin/env bash
# Markdown section / table primitives for receipt-homed accounting (issue #201),
# in bash + POSIX awk (issue #355 took python off the commit path).
#
# Accounting rows live under a receipt's `## Accounting` section as `### Costs`
# and `### Steering` sub-tables. This file knows how to find that region, emit
# its data rows, and splice a new row into the tail of a sub-table — creating
# the section / sub-table / file when absent. The steering-row schema lives in
# sibling `steering.sh`; the generic Markdown plumbing lives here.
#
# This file is deliberately a verbatim twin of the one in the sibling
# agent-token-accounting directive: a directive folder installs as a
# self-contained unit, so shared plumbing is duplicated rather than reached
# across directive boundaries (the same choice the retired receipt_io.py pair
# made). Keep the two in sync when either changes.
#
# Sourced by check.sh and the sibling libs. Bash 3.2
# compatible (no associative arrays); every awk program is POSIX and receives
# its parameters through the environment (never `-v`, whose values take a
# second pass of backslash-escape interpretation).

RECEIPT_ACCOUNTING_NOTE='<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->'

# ── Region scanner ────────────────────────────────────────────────────────
# The awk prelude shared by every reader below. `## Accounting` opens the
# section; a following `## `/`# ` heading closes it; a `### ` heading inside it
# opens the named sub-table or closes it. Mirrors the region rules the retired
# receipt_io.py used, so v1–v5 receipts keep parsing identically.
_RECEIPT_AWK_REGION='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function ncells(line, c,   n, i) {
    n = split(line, c, "|")
    if (n < 3) { return 0 }
    for (i = 1; i <= n - 2; i++) { c[i] = trim(c[i + 1]) }
    delete c[n - 1]; delete c[n]
    return n - 2
}
function is_skip_row(c, m, first_header,   i, all) {
    if (m < 1) { return 1 }
    if (c[1] == first_header) { return 1 }
    if (c[1] == "") { return 1 }
    if (c[1] ~ /^-+$/) { return 1 }
    all = 1
    for (i = 1; i <= m; i++) { if (c[i] != "" && c[i] !~ /^-+$/) { all = 0 } }
    return all
}
'

# receipt_rows <file> <subheading>
#   Emit the raw data-row lines (leading `|`) of the receipt's <subheading>
#   sub-table under `## Accounting`. Silent when the file / section is absent.
receipt_rows() {
    [ -f "$1" ] || return 0
    RECEIPT_SUB="$2" awk "
$_RECEIPT_AWK_REGION"'
BEGIN { want = ENVIRON["RECEIPT_SUB"]; in_acc = 0; in_sub = 0 }
{ t = trim($0) }
t == "## Accounting" { in_acc = 1; in_sub = 0; next }
in_acc && ($0 ~ /^## / || $0 ~ /^# /) { in_acc = 0; in_sub = 0; next }
in_acc && $0 ~ /^### / { in_sub = (t == want) ? 1 : 0; next }
in_acc && in_sub && t ~ /^\|/ { print $0 }
' "$1"
}

# receipt_safe_cell <text> [max-len] [ellipsis]
#   Sanitise free text for a table cell: drop control characters and `|`, cut
#   at the first backslash (BSD `ps` renders an embedded newline as a literal
#   `\012`), trim, then truncate. With a non-empty third argument an over-long
#   value is truncated to max-1 and marked with `…`. Same contract the retired
#   receipt_io.py / ledger.py pair had.
receipt_safe_cell() {
    local s="$1" max="${2:-80}" ellipsis="${3:-}"
    s="$(printf '%s' "$s" | tr -d '|' | tr -d '\000-\037\177')"
    s="${s%%\\*}"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    if [ -n "$ellipsis" ] && [ "${#s}" -gt "$max" ]; then
        printf '%s…' "${s:0:$((max - 1))}"
        return 0
    fi
    printf '%s' "${s:0:$max}"
}

# receipt_insert_row <file> <subheading> <header> <separator> <row-line>
#   Splice <row-line> at the tail of <subheading>'s table under
#   `## Accounting`, creating the file / section / sub-table as needed.
receipt_insert_row() {
    local file="$1" sub="$2" header="$3" separator="$4" row="$5"
    local tmp
    mkdir -p "$(dirname "$file")"
    [ -f "$file" ] || : > "$file"
    tmp="$file.gk-tmp.$$"
    RECEIPT_SUB="$sub" RECEIPT_HEADER="$header" RECEIPT_SEP="$separator" \
    RECEIPT_ROW="$row" RECEIPT_NOTE="$RECEIPT_ACCOUNTING_NOTE" awk "
$_RECEIPT_AWK_REGION"'
BEGIN {
    sub_h = ENVIRON["RECEIPT_SUB"]; hdr = ENVIRON["RECEIPT_HEADER"]
    sep = ENVIRON["RECEIPT_SEP"]; row = ENVIRON["RECEIPT_ROW"]
    note = ENVIRON["RECEIPT_NOTE"]
}
{ L[++n] = $0 }
END {
    acc = 0
    for (i = 1; i <= n; i++) { if (trim(L[i]) == "## Accounting") { acc = i; break } }
    if (acc == 0) {
        if (n > 0 && trim(L[n]) != "") { L[++n] = "" }
        L[++n] = "## Accounting"; L[++n] = ""; L[++n] = note; L[++n] = ""
        acc = n - 3
    }
    sec = n + 1
    for (i = acc + 1; i <= n; i++) {
        if (L[i] ~ /^## / || L[i] ~ /^# /) { sec = i; break }
    }
    s = 0
    for (i = acc + 1; i < sec; i++) { if (trim(L[i]) == sub_h) { s = i; break } }
    bn = 0
    if (s == 0) {
        if (sec > 1 && trim(L[sec - 1]) != "") { B[++bn] = "" }
        B[++bn] = sub_h; B[++bn] = ""; B[++bn] = hdr; B[++bn] = sep; B[++bn] = row
        ins = sec
    } else {
        i = s + 1
        while (i < sec && trim(L[i]) == "") { i++ }
        while (i < sec && L[i] ~ /^[ \t]*\|/) { i++ }
        B[++bn] = row
        ins = i
    }
    for (i = 1; i < ins; i++) { print L[i] }
    for (j = 1; j <= bn; j++) { print B[j] }
    for (i = ins; i <= n; i++) { print L[i] }
}
' "$file" > "$tmp" && mv "$tmp" "$file"
}

# receipt_resolve <receipts-dir> <issue>
#   The receipt a row for issue N belongs in: an existing
#   `issue-N.md` / `issue-N-<slug>.md` (first, deterministically, when several),
#   else the slugless `issue-N.md` create-if-absent default. The file itself is
#   created by the first `receipt_insert_row` — an accounting-only stub the
#   agent later fleshes out (or renames with a slug).
receipt_resolve() {
    # Byte-order collation, so "issue-N-slug.md" sorts before "issue-N.md"
    # exactly as the retired python `sorted()` did.
    local LC_ALL=C
    local dir="$1" n="${2#\#}" f base match="" match_base=""
    if [ -d "$dir" ]; then
        for f in "$dir"/issue-"$n".md "$dir"/issue-"$n"-*.md; do
            [ -f "$f" ] || continue
            base="$(basename "$f")"
            printf '%s' "$base" | grep -qE "^issue-$n(-[a-z0-9]+)*\.md$" || continue
            if [ -z "$match" ] || [[ "$base" < "$match_base" ]]; then
                match="$f"; match_base="$base"
            fi
        done
    fi
    if [ -n "$match" ]; then
        printf '%s\n' "$match"
    else
        printf '%s\n' "$dir/issue-$n.md"
    fi
}
