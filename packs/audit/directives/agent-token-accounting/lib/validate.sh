#!/usr/bin/env bash
# Receipt Costs-table validation for agent-token-accounting, in bash + POSIX awk
# (issue #355 took python off every path this directive touches).
#
# `costs_validate_dir <receipts-dir>` prints one violation per line and exits
# non-zero when any fired. It is the whole Mode-B check and the repo-wide half
# of Mode A, so it runs in CI and on every commit.
#
# What it checks, and just as importantly what it does NOT:
#
#   It validates the SHAPE of a v6 row — cell count, a real date, an identity,
#   integer-or-`-` token cells, decimal-or-`-` dollars, a provenance label from
#   the closed set, and one row per session per receipt.
#
#   It never checks a NUMBER for equality against anything. The numbers are
#   best-effort measurements taken off the commit path, from a session that is
#   still running; they are expected to move, and an unresolved row carrying
#   `-` everywhere is a legitimate, honest state that CI must accept. A checker
#   that compared them would be asserting that a live session had stopped.
#
#   Legacy rows are recognised by cell count (17 = v5, 16 = v4, 12 = v3) and
#   structurally tolerated. They were written under a schema whose rules no
#   longer describe them, so re-validating them would only manufacture
#   violations nobody can fix; receipts on the trunk are frozen anyway.
#
# Sourced by check.sh after sibling `receipt.sh` (for `$_RECEIPT_AWK_REGION`).

costs_validate_dir() {
    local dir="$1" f
    local LC_ALL=C
    [ -d "$dir" ] || return 0
    local files
    files=()
    for f in "$dir"/issue-*.md; do
        [ -f "$f" ] && files[${#files[@]}]="$f"
    done
    [ ${#files[@]} -eq 0 ] && return 0
    COSTS_SOURCES_SET="${COSTS_SOURCES:- harness-feed session-file server manual unresolved }" awk "
$_RECEIPT_AWK_REGION"'
function basename(p,   n, a) { n = split(p, a, "/"); return a[n] }
function is_num_cell(s) { return (s == "-" || s ~ /^[0-9]+$/) }
function is_cost_cell(s) { return (s == "-" || s ~ /^[0-9]+(\.[0-9]+)?$/) }
function is_date(s) { return (s ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) }
function known_source(s) { if (s == "") { return 0 } return (index(sources, " " s " ") > 0) }
function emit(v) { V[++nv] = v }

# `q` carries the apostrophe the messages need — the program itself is a
# single-quoted shell string and POSIX awk has no \x escape.
BEGIN {
    nv = 0; q = sprintf("%c", 39)
    sources = ENVIRON["COSTS_SOURCES_SET"]
}

FNR == 1 { in_acc = 0; in_sub = 0; fname = basename(FILENAME) }
{ t = trim($0) }
t == "## Accounting" { in_acc = 1; in_sub = 0; next }
in_acc && ($0 ~ /^## / || $0 ~ /^# /) { in_acc = 0; in_sub = 0; next }
in_acc && $0 ~ /^### / { in_sub = (t == "### Costs") ? 1 : 0; next }
!(in_acc && in_sub && t ~ /^\|/) { next }

{
    m = ncells($0, c)
    if (is_skip_row(c, m, "date")) { next }

    # Legacy shapes: parsed, counted, not judged.
    if (m == 17 || m == 16 || m == 12) { next }

    if (m != 10) {
        emit(fname ":" FNR " — row has " m " cells, expected 10 (v6: date | harness | session | model | input | cache-create | cache-read | output | cost-usd | source); 17/16/12-cell legacy rows are tolerated")
        next
    }

    day = c[1]; harness = c[2]; session = c[3]; model = c[4]
    ti = c[5]; tcc = c[6]; tcr = c[7]; tout = c[8]; cost = c[9]; src = c[10]
    where = fname " — row " q "" harness "/" session "" q

    if (!is_date(day)) {
        emit(where " has a malformed date " q "" day "" q " (expected YYYY-MM-DD — the day this session first touched the issue)")
    }
    if (harness !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/) {
        emit(fname ":" FNR " — row has an empty or malformed harness " q "" harness "" q " (a v6 row is identified by harness + session)")
    }
    if (session == "") {
        emit(where " has an empty session cell (write the literal - when the harness does not name its session)")
    }
    if (model == "") {
        emit(where " has an empty model cell (write the literal - when no model is known)")
    }
    if (!is_num_cell(ti) || !is_num_cell(tcc) || !is_num_cell(tcr) || !is_num_cell(tout)) {
        emit(where " has a token cell that is neither a non-negative integer nor - (input=" ti ", cache-create=" tcc ", cache-read=" tcr ", output=" tout ")")
    }
    if (!is_cost_cell(cost)) {
        emit(where " has a cost-usd cell " q "" cost "" q " that is neither a non-negative decimal nor - (the kit never prices; the cell holds the harness" q "s own figure or nothing)")
    }
    if (!known_source(src)) {
        emit(where " has an unknown source " q "" src "" q " (one of: harness-feed, session-file, server, manual, unresolved)")
    }

    k = fname SUBSEP harness SUBSEP session
    if (!(k in seen)) { seen[k] = 1; korder[++nk] = k; kfile[k] = fname; kname[k] = harness "/" session }
    else { dup[k] = 1 }
}

END {
    for (i = 1; i <= nk; i++) {
        k = korder[i]
        if (k in dup) {
            emit(kfile[k] " — session " q "" kname[k] "" q " has more than one Costs row (v6 keeps one row per session per issue, updated in place)")
        }
    }
    for (i = 1; i <= nv; i++) { print V[i] }
    exit (nv > 0) ? 1 : 0
}
' "${files[@]}"
}
