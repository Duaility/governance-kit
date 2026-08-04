#!/usr/bin/env bash
# Receipt cost-table validation for agent-token-accounting, in bash + POSIX awk
# (issue #355 took python off the commit path).
#
# `costs_validate_dir <receipts-dir>` prints one violation per line and exits
# non-zero when any fired. It is the whole Mode-B check and the repo-wide half
# of Mode A, so it runs on every commit and in CI.
#
# Rules, by row version (dispatched on cell count — v5 = 17, v4 = 16,
# legacy v3 = 12):
#
#   every version   cost-key non-empty; agent / session / issue non-empty;
#                   issue looks like `#123` and matches the receipt's own
#                   issue; the five token cells are non-negative integers;
#                   `new-work == input + cache-create + output`; cost-usd is
#                   empty or a non-negative decimal; cost-key unique within a
#                   receipt and globally across `receipts/*.md`.
#   v4 + v5         each `cum-*` is a non-negative integer no smaller than its
#                   own delta; per session the cumulative columns are monotonic
#                   and each delta reconciles against the nearest co-visible
#                   predecessor.
#   v5 only         `source` names the runtime adapter that wrote the row.
#   v3 + v4 only    a row that names a model must carry a cost-usd (those rows
#                   were written when the kit still priced them). v5 drops
#                   every pricing rule: the harness reports the dollars or the
#                   cell stays blank.
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
function is_uint(s) { return (s ~ /^[0-9]+$/) }
function is_dec(s)  { return (s ~ /^-?[0-9]+(\.[0-9]+)?$/) }
function short(s)   { return substr(s, 1, 16) "…" }
function emit(v)    { V[++nv] = v }
function mono_msg(sess, comp, from_v, from_k, to_v, to_k, qc) {
    return "receipts — session " qc "" short(sess) "" qc " " comp " decreases from " from_v " (row " qc "" from_k "" qc ") to " to_v " (row " qc "" to_k "" qc ") — cumulative counters are monotonic; this is corruption or a hand-edit"
}
function delta_msg(k, comp, dlt, cum_v, base_v, where, sess, qc,   diff) {
    diff = cum_v - base_v
    return "receipts — cost row " qc "" k "" qc " " comp " delta (" dlt ") != cum(n) − cum(n−1) (" cum_v " − " base_v " = " diff ") against predecessor " where " for session " qc "" short(sess) "" qc " — backfill the delta column to the reconciled value."
}

# `q` / `bq` carry the apostrophe and backtick the quoted violation messages
# need — the program itself is a single-quoted shell string, and POSIX awk has
# no \x escape, so they are built with sprintf("%c", …).
BEGIN { nv = 0; nr_rows = 0; nsess = 0; q = sprintf("%c", 39); bq = sprintf("%c", 96) }

FNR == 1 {
    in_acc = 0; in_sub = 0
    fname = basename(FILENAME)
    issue_n = issue_from_name(fname)
}
{ t = trim($0) }
t == "## Accounting" { in_acc = 1; in_sub = 0; next }
in_acc && ($0 ~ /^## / || $0 ~ /^# /) { in_acc = 0; in_sub = 0; next }
in_acc && $0 ~ /^### / { in_sub = (t == "### Costs") ? 1 : 0; next }
!(in_acc && in_sub && t ~ /^\|/) { next }

{
    m = ncells($0, c)
    if (is_skip_row(c, m, "cost-key")) { next }
    if (m != 17 && m != 16 && m != 12) {
        emit(fname ":" FNR " — row has " m " cells, expected 17 (v5), 16 (v4) or 12 (legacy v3)")
        next
    }
    key = c[1]; agent = c[2]; session = c[3]; issue = c[4]; model = c[5]
    ti = c[6]; tcc = c[7]; tcr = c[8]; tout = c[9]; nw = c[10]; cost = c[11]
    if (m >= 16) { ci = c[12]; cccr = c[13]; ccrr = c[14]; co = c[15] }
    src = (m == 17) ? c[16] : ""

    if (key == "") { emit(fname ":" FNR " — empty cost-key"); next }
    filekey = fname SUBSEP key
    if (!(filekey in fkcount)) { fkorder[++nfk] = filekey; fkfile[filekey] = fname; fkname[filekey] = key }
    fkcount[filekey]++

    if (agent == "" || session == "" || issue == "") {
        emit(fname " — row " q "" key "" q " has empty agent/session/issue field")
    }
    if (issue != "" && issue !~ /^#[1-9][0-9]*$/) {
        emit(fname " — row " q "" key "" q " issue " q "" issue "" q " must look like " q "#123" q "")
    } else if (issue != "" && issue_n != "" && issue != issue_n) {
        emit(fname " — row " q "" key "" q " issue " q "" issue "" q " does not match this receipt" q "s issue " q "" issue_n "" q " (a cost row lives in the receipt for its own issue)")
    }

    if (!is_uint(ti) || !is_uint(tcc) || !is_uint(tcr) || !is_uint(tout) || !is_uint(nw)) {
        emit(fname " — row " q "" key "" q " has non-integer or negative token counts (input=" ti ", cache_create=" tcc ", cache_read=" tcr ", output=" tout ", new_work=" nw ")")
        next
    }
    expect_nw = ti + tcc + tout
    if (nw + 0 != expect_nw) {
        emit(fname " — row " q "" key "" q " has new_work=" nw " but input+cache_create+output=" expect_nw " (cache_read=" tcr " is tracked but excluded from new_work)")
    }

    if (cost != "" && !is_dec(cost)) {
        emit(fname " — row " q "" key "" q " has non-numeric cost_usd " q "" cost "" q "")
    } else if (cost != "" && cost + 0 < 0) {
        emit(fname " — row " q "" key "" q " has negative cost_usd " q "" cost "" q "")
    } else if (cost == "" && model != "" && m != 17) {
        emit(fname " — row " q "" key "" q " names model " q "" model "" q " but has empty cost_usd (legacy v3/v4 rows carried a kit-computed price; backfill the cell, or migrate the row to v5 where cost-usd is whatever the harness reported — possibly nothing)")
    }

    if (m == 17 && src !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/) {
        emit(fname " — row " q "" key "" q " has an empty or malformed source " q "" src "" q " (v5 rows name the runtime adapter that produced them, e.g. claude-code / codex / manual)")
    }

    hascum = 0
    if (m >= 16) {
        if (!is_uint(ci) || !is_uint(cccr) || !is_uint(ccrr) || !is_uint(co)) {
            emit(fname " — row " q "" key "" q " has non-integer or negative cumulative counts (cum_input=" ci ", cum_cache_create=" cccr ", cum_cache_read=" ccrr ", cum_output=" co ")")
        } else {
            hascum = 1
            if (ci + 0 < ti + 0)    { emit(fname " — row " q "" key "" q " cum_input (" ci ") is less than its input delta (" ti ") — a cumulative counter cannot be smaller than the slice it contains") }
            if (cccr + 0 < tcc + 0) { emit(fname " — row " q "" key "" q " cum_cache_create (" cccr ") is less than its cache_create delta (" tcc ") — a cumulative counter cannot be smaller than the slice it contains") }
            if (ccrr + 0 < tcr + 0) { emit(fname " — row " q "" key "" q " cum_cache_read (" ccrr ") is less than its cache_read delta (" tcr ") — a cumulative counter cannot be smaller than the slice it contains") }
            if (co + 0 < tout + 0)  { emit(fname " — row " q "" key "" q " cum_output (" co ") is less than its output delta (" tout ") — a cumulative counter cannot be smaller than the slice it contains") }
        }
    }

    if (hascum && session != "") {
        r = ++nr_rows
        R_file[r] = fname; R_key[r] = key; R_sess[r] = session
        R_in[r] = ti + 0; R_cc[r] = tcc + 0; R_cr[r] = tcr + 0; R_out[r] = tout + 0
        R_ci[r] = ci + 0; R_ccc[r] = cccr + 0; R_ccr[r] = ccrr + 0; R_co[r] = co + 0
        R_cum[r] = R_ci[r] + R_ccc[r] + R_ccr[r] + R_co[r]
        R_dlt[r] = R_in[r] + R_cc[r] + R_cr[r] + R_out[r]
        if (!(session in seensess)) { seensess[session] = 1; SESS[++nsess] = session }
    }
}

END {
    # ── cost-key uniqueness: within a receipt, then across receipts ──
    for (i = 1; i <= nfk; i++) {
        fk = fkorder[i]
        if (fkcount[fk] > 1) {
            emit(fkfile[fk] " — cost-key " q "" fkname[fk] "" q " appears " fkcount[fk] " times (must be unique)")
        }
    }
    for (i = 1; i <= nfk; i++) {
        fk = fkorder[i]; k = fkname[fk]
        if (k in firstfile) {
            if (firstfile[k] != fkfile[fk]) {
                emit("receipts — cost-key " q "" k "" q " appears in both " firstfile[k] " and " fkfile[fk] " (must be globally unique)")
            }
        } else { firstfile[k] = fkfile[fk] }
    }

    # ── per-session monotonicity + delta reconciliation (v4 + v5 rows) ──
    for (s = 1; s <= nsess; s++) {
        sess = SESS[s]
        n = 0
        for (i = 1; i <= nr_rows; i++) { if (R_sess[i] == sess) { IDX[++n] = i } }
        # stable insertion sort by cumulative total
        for (i = 2; i <= n; i++) {
            v = IDX[i]; j = i - 1
            while (j >= 1 && R_cum[IDX[j]] > R_cum[v]) { IDX[j + 1] = IDX[j]; j-- }
            IDX[j + 1] = v
        }
        for (i = 2; i <= n; i++) {
            pa = IDX[i - 1]; pb = IDX[i]
            if (R_ci[pb]  < R_ci[pa])  { emit(mono_msg(sess, "cum_input", R_ci[pa], R_key[pa], R_ci[pb], R_key[pb], q)) }
            if (R_ccc[pb] < R_ccc[pa]) { emit(mono_msg(sess, "cum_cache_create", R_ccc[pa], R_key[pa], R_ccc[pb], R_key[pb], q)) }
            if (R_ccr[pb] < R_ccr[pa]) { emit(mono_msg(sess, "cum_cache_read", R_ccr[pa], R_key[pa], R_ccr[pb], R_key[pb], q)) }
            if (R_co[pb]  < R_co[pa])  { emit(mono_msg(sess, "cum_output", R_co[pa], R_key[pa], R_co[pb], R_key[pb], q)) }
        }
        for (i = 1; i <= n; i++) {
            r = IDX[i]
            pred = 0
            for (j = 1; j <= n; j++) {
                cand = IDX[j]
                if (R_cum[cand] < R_cum[r] && (pred == 0 || R_cum[cand] > R_cum[pred])) { pred = cand }
            }
            prev_total = (pred == 0) ? 0 : R_cum[pred]
            implied = R_cum[r] - R_dlt[r]
            if (implied < prev_total) {
                gap = R_cum[r] - prev_total
                emit("receipts — cost row " q "" R_key[r] "" q " claims a per-commit delta of " R_dlt[r] " tokens, but its cumulative coordinate sits only " gap " above the previous co-visible row " q "" R_key[pred] "" q " for session " q "" short(sess) "" q " — the claim double-counts tokens already attributed to an earlier commit. Backfill the delta columns to cum(n) − cum(n−1), or add a " bq "governance: allow-agent-token-accounting <reason>" bq " waiver if the predecessor is genuinely unrecoverable.")
                continue
            }
            if (implied > prev_total) { continue }
            where = "the session origin (0)"
            if (pred != 0) { where = "row " q "" R_key[pred] "" q "" }
            b_in  = (pred == 0) ? 0 : R_ci[pred]
            b_cc  = (pred == 0) ? 0 : R_ccc[pred]
            b_cr  = (pred == 0) ? 0 : R_ccr[pred]
            b_out = (pred == 0) ? 0 : R_co[pred]
            if (R_in[r]  != R_ci[r]  - b_in)  { emit(delta_msg(R_key[r], "input", R_in[r], R_ci[r], b_in, where, sess, q)) }
            if (R_cc[r]  != R_ccc[r] - b_cc)  { emit(delta_msg(R_key[r], "cache_create", R_cc[r], R_ccc[r], b_cc, where, sess, q)) }
            if (R_cr[r]  != R_ccr[r] - b_cr)  { emit(delta_msg(R_key[r], "cache_read", R_cr[r], R_ccr[r], b_cr, where, sess, q)) }
            if (R_out[r] != R_co[r]  - b_out) { emit(delta_msg(R_key[r], "output", R_out[r], R_co[r], b_out, where, sess, q)) }
        }
    }

    for (i = 1; i <= nv; i++) { print V[i] }
    exit (nv > 0) ? 1 : 0
}
' "${files[@]}"
}
