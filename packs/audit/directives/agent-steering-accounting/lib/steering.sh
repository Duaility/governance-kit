#!/usr/bin/env bash
# Steering-row schema, append and validation — bash + POSIX awk (issue #355
# took python off the commit path).
#
# Rows live in per-issue receipts (issue #201): each is appended under the
# `## Accounting` → `### Steering` sub-table of `receipts/issue-<N>.md`.
#
# Row schema — v2 (9 columns, issue #229):
#
#   | steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
#
# `ordinal` and `timestamp` are the event's absolute transcript coordinates:
# `ordinal` is its 1-based position in the session's deterministic event stream.
# Dedup is identity-based — a `(session, ordinal)` pair is appended once, ever.
# The pair is also what makes a cross-branch duplicate DETECTABLE: the same
# event re-appended on a sibling branch lands a second row with the same
# `(session, ordinal)`, which validate-dir flags after the merge.
#
# `type` ∈ interrupt | correction · `tier` ∈ structural | classifier | lexical ·
# `steer-key` = steer-<session-short>-<epoch>-<idx> · `issue` = #N (required —
# every accounted event resolves to an issue, which is the receipt that homes it).
#
# Legacy v1 rows (7 columns, no ordinal/timestamp) keep parsing and are
# validated to the v1 rules; the ordinal checks apply to v2 rows only.
#
# Markdown plumbing lives in sibling `receipt.sh` (source it first). This file
# is both a source-able library and a small CLI, so the fresh-context sub-agent
# that records events has one command to call:
#
#   bash lib/steering.sh append-row <receipt> <steer-key> <session> <issue> \
#        <type> <tier> <user-reason> <commit> <ordinal> <timestamp>
#   bash lib/steering.sh validate-dir <receipts-dir>
#   bash lib/steering.sh existing-ordinals <receipts-dir> <session>

STEERING_SUBHEADING="### Steering"
STEERING_COLS_V2=9
STEERING_COLS_V1=7
STEERING_HEADER="| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |"
STEERING_SEPARATOR="| --- | --- | --- | --- | --- | --- | --- | --- | --- |"
STEERING_USER_REASON_MAX=240

# steering_rows <receipt>  → the receipt's Steering data rows, raw.
steering_rows() {
    receipt_rows "$1" "$STEERING_SUBHEADING"
}

# steering_resolve <receipts-dir> <issue>  → the receipt for issue N.
steering_resolve() {
    receipt_resolve "$1" "$2"
}

# steering_append_row <receipt> <steer-key> <session> <issue> <type> <tier> \
#                     <user-reason> <commit> <ordinal> <timestamp>
steering_append_row() {
    local receipt="$1" key="$2" session="$3" issue="$4" typ="$5" tier="$6"
    local reason="$7" commit="$8" ordinal="$9" ts="${10}"
    local row
    key="$(receipt_safe_cell "$key" 120)"
    session="$(receipt_safe_cell "$session" 120)"
    issue="$(receipt_safe_cell "$issue" 40)"
    typ="$(receipt_safe_cell "$typ" 40)"
    tier="$(receipt_safe_cell "$tier" 40)"
    reason="$(receipt_safe_cell "$reason" "$STEERING_USER_REASON_MAX" truncate)"
    commit="$(receipt_safe_cell "$commit" 80 truncate)"
    ordinal="$(receipt_safe_cell "$ordinal" 20)"
    ts="$(receipt_safe_cell "$ts" 40)"
    row="| $key | $session | $issue | $typ | $tier | $reason | $commit | $ordinal | $ts |"
    receipt_insert_row "$receipt" "$STEERING_SUBHEADING" \
        "$STEERING_HEADER" "$STEERING_SEPARATOR" "$row"
}

# steering_existing_ordinals <receipts-dir> <session>
#   The ordinals already recorded for <session>, ascending — the identity-dedup
#   boundary the recorder consults before appending an event.
steering_existing_ordinals() {
    local dir="$1" f
    [ -d "$dir" ] || return 0
    for f in "$dir"/issue-*.md; do
        [ -f "$f" ] || continue
        steering_rows "$f"
    done | STEERING_SESSION="$2" awk "
$_RECEIPT_AWK_REGION"'
BEGIN { want = ENVIRON["STEERING_SESSION"] }
{
    m = ncells($0, c)
    if (is_skip_row(c, m, "steer-key")) { next }
    if (m != 9) { next }
    if (c[2] != want) { next }
    if (c[8] !~ /^[0-9]+$/) { next }
    print c[8]
}
' | sort -n | uniq
}

# steering_validate_dir <receipts-dir>
#   Print one violation per line; exit non-zero when any fired. Checks, in
#   order: per-row shape (7 or 9 cells), well-formed steer-key, append-only
#   embedded-epoch order, non-empty session, receipt-homed `#N` issue,
#   type/tier in the allowed sets, positive per-session strictly-increasing
#   ordinals (v2 only), steer-key uniqueness within a receipt, then — across
#   receipts — global steer-key uniqueness and `(session, ordinal)` identity.
steering_validate_dir() {
    local dir="$1" f
    local LC_ALL=C
    [ -d "$dir" ] || return 0
    local files
    files=()
    for f in "$dir"/issue-*.md; do
        [ -f "$f" ] && files[${#files[@]}]="$f"
    done
    [ ${#files[@]} -eq 0 ] && return 0
    awk "
$_RECEIPT_AWK_REGION"'
function basename(p,   n, a) { n = split(p, a, "/"); return a[n] }
function issue_from_name(nm,   s) {
    if (nm !~ /^issue-[1-9][0-9]*(-[a-z0-9]+)*\.md$/) { return "" }
    s = nm
    sub(/^issue-/, "", s)
    sub(/(-[a-z0-9]+)*\.md$/, "", s)
    return "#" s
}
function short(s) { return substr(s, 1, 16) "…" }
function emit(v)  { V[++nv] = v }

# `q` carries the apostrophe the quoted violation messages need — the program
# is a single-quoted shell string and POSIX awk has no \x escape.
BEGIN { nv = 0; q = sprintf("%c", 39); bq = sprintf("%c", 96) }

FNR == 1 {
    in_acc = 0; in_sub = 0
    fname = basename(FILENAME)
    issue_n = issue_from_name(fname)
    last_epoch = -1
    split("", lastord)
}
{ t = trim($0) }
t == "## Accounting" { in_acc = 1; in_sub = 0; next }
in_acc && ($0 ~ /^## / || $0 ~ /^# /) { in_acc = 0; in_sub = 0; next }
in_acc && $0 ~ /^### / { in_sub = (t == "### Steering") ? 1 : 0; next }
!(in_acc && in_sub && t ~ /^\|/) { next }

{
    m = ncells($0, c)
    if (is_skip_row(c, m, "steer-key")) { next }
    if (m != 9 && m != 7) {
        emit(fname ":" FNR " — row has " m " cells, expected 7 (legacy) or 9")
        next
    }
    key = c[1]; session = c[2]; issue = c[3]; typ = c[4]; tier = c[5]
    ordinal = (m == 9) ? c[8] : ""

    if (key == "") { emit(fname ":" FNR " — empty steer-key"); next }

    if (key !~ /^steer-[A-Za-z0-9]+-[0-9]+-[0-9]+$/) {
        emit(fname " — row " q "" key "" q " has malformed steer-key (expected steer-<session-short>-<epoch>-<idx>)")
    } else {
        epoch = key
        sub(/-[0-9]+$/, "", epoch)
        sub(/^.*-/, "", epoch)
        epoch = epoch + 0
        if (epoch < last_epoch) {
            emit(fname " — row " q "" key "" q " is out of order (epoch " epoch " < previous " last_epoch "; rows are append-only)")
        }
        if (epoch > last_epoch) { last_epoch = epoch }
    }

    if (session == "") { emit(fname " — row " q "" key "" q " has empty session") }
    if (issue == "") {
        emit(fname " — row " q "" key "" q " has empty issue (every steering event must resolve to an issue; receipt rows are never issue-less)")
    } else if (issue !~ /^#[1-9][0-9]*$/) {
        emit(fname " — row " q "" key "" q " issue " q "" issue "" q " must look like " q "#123" q "")
    } else if (issue_n != "" && issue != issue_n) {
        emit(fname " — row " q "" key "" q " issue " q "" issue "" q " does not match this receipt" q "s issue " q "" issue_n "" q "")
    }
    if (typ != "interrupt" && typ != "correction") {
        emit(fname " — row " q "" key "" q " has unknown type " q "" typ "" q " (expected one of: correction, interrupt)")
    }
    if (tier != "structural" && tier != "classifier" && tier != "lexical") {
        emit(fname " — row " q "" key "" q " has unknown tier " q "" tier "" q " (expected one of: classifier, lexical, structural)")
    }

    if (m == 9) {
        if (ordinal !~ /^[0-9]+$/ || ordinal + 0 < 1) {
            emit(fname " — row " q "" key "" q " has malformed ordinal " q "" ordinal "" q " (expected a positive integer)")
        } else if (session != "") {
            ordn = ordinal + 0
            if (session in lastord) {
                prev = lastord[session]
                if (ordn <= prev) {
                    emit(fname " — row " q "" key "" q " ordinal " ordn " is not greater than the previous ordinal " prev " for session " q "" short(session) "" q " (per-session ordinals are strictly increasing in append order)")
                }
                if (ordn > prev) { lastord[session] = ordn }
            } else {
                lastord[session] = ordn
            }
            ident = session SUBSEP ordn
            if (ident in identfile) {
                emit("receipts — steering event (session " q "" short(session) "" q ", ordinal " ordn ") appears in both " identfile[ident] " and " fname " — the same transcript event was recorded twice (cross-branch re-append); drop the duplicate row or add a " bq "governance: allow-agent-steering-accounting <reason>" bq " waiver")
            } else {
                identfile[ident] = fname
            }
        }
    }

    filekey = fname SUBSEP key
    if (!(filekey in fkcount)) { fkorder[++nfk] = filekey; fkfile[filekey] = fname; fkname[filekey] = key }
    fkcount[filekey]++
}

END {
    for (i = 1; i <= nfk; i++) {
        fk = fkorder[i]
        if (fkcount[fk] > 1) {
            emit(fkfile[fk] " — steer-key " q "" fkname[fk] "" q " appears " fkcount[fk] " times (must be unique)")
        }
    }
    for (i = 1; i <= nfk; i++) {
        fk = fkorder[i]; k = fkname[fk]
        if (k in firstfile) {
            if (firstfile[k] != fkfile[fk]) {
                emit("receipts — steer-key " q "" k "" q " appears in both " firstfile[k] " and " fkfile[fk] " (must be globally unique)")
            }
        } else { firstfile[k] = fkfile[fk] }
    }
    for (i = 1; i <= nv; i++) { print V[i] }
    exit (nv > 0) ? 1 : 0
}
' "${files[@]}"
}

# ── CLI ───────────────────────────────────────────────────────────────────
# Executed (not sourced) this file is the recorder's entry point.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -u
    _STEERING_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1090
    . "$_STEERING_HERE/receipt.sh"

    _steering_die() { printf 'steering: %s\n' "$1" >&2; exit 2; }

    case "${1:-}" in
        validate-dir)
            [ $# -eq 2 ] || _steering_die "validate-dir takes: <receipts-dir>"
            steering_validate_dir "$2"
            ;;
        existing-ordinals)
            [ $# -eq 3 ] || _steering_die "existing-ordinals takes: <receipts-dir> <session>"
            steering_existing_ordinals "$2" "$3"
            ;;
        append-row)
            [ $# -eq 11 ] || _steering_die "append-row takes: <receipt> <steer-key> <session> <issue> <type> <tier> <user-reason> <commit> <ordinal> <timestamp>"
            case "$6" in
                interrupt|correction) ;;
                *) _steering_die "unknown type '$6' (expected interrupt or correction)" ;;
            esac
            case "$7" in
                structural|classifier|lexical) ;;
                *) _steering_die "unknown tier '$7' (expected structural, classifier or lexical)" ;;
            esac
            printf '%s' "$3" | grep -qE '^steer-[A-Za-z0-9]+-[0-9]+-[0-9]+$' \
                || _steering_die "malformed steer-key '$3'"
            printf '%s' "${10}" | grep -qE '^[1-9][0-9]*$' \
                || _steering_die "ordinal must be a positive integer (got '${10}')"
            steering_append_row "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}"
            ;;
        *)
            _steering_die "usage: steering.sh <validate-dir|existing-ordinals|append-row> ..."
            ;;
    esac
fi
