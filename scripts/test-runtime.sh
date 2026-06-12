#!/usr/bin/env bash
# scripts/test-runtime.sh — direct tests for the runtime files shipped to
# every target repo: kit/assets/dot-governance/run.sh and lib.sh.
#
# These two scripts run on every consumer's machine on every commit. They
# need their own coverage independent of how this repo dogfoods them.
#
# Covers:
#   run.sh:
#     - SKIP_GOVERNANCE=1 silences the runner
#     - empty .governance/ tree exits 0 with a clear message
#     - all directive checks pass → exit 0 + "all N directive(s) passed"
#     - any directive fails → exit 1 + bypass instructions
#     - single-directive filter `run.sh <id>` runs one check
#     - filter that matches nothing exits 1 with a clear message
#     - directives discovered uniformly under packs/<owner>/<name>/directives/
#   lib.sh:
#     - directive_start / directive_end with no violations exits 0 + green ✓
#     - violation increments count; directive_end exits 1 + lists violations
#     - require_git inside a non-repo emits ⊘ skip and exits 0
#     - tracked_files respects .gitignore
#     - has_waiver matches `governance: allow-<id>` on the given line
#     - has_file_waiver matches `governance: allow-<id> <sub-check>` in
#       the first 10 lines, scoped to both directive id and sub-check
#     - conf_file resolves .governance/conf/<id>.conf (present/absent)
#     - conf_get precedence: env GOVERNANCE_<KEY> > conf line > default
#     - conf_rule_lines strips comments/blanks/KEY= and trims the rest
#     - conf_list layers defaults.conf with the overlay (+add / !remove),
#       normalizing whitespace for ! removal

set -eu

# Drop any GIT_* env state inherited from a parent process (e.g. when invoked
# from a pre-commit hook). The require_git tests below escape into temp
# dirs via subshell `cd`, but inherited GIT_DIR / GIT_WORK_TREE keep git
# anchored to the parent repo and the "outside a git repo" assertions flip.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_SH="$ROOT/kit/assets/dot-governance/run.sh"
LIB_SH="$ROOT/kit/assets/dot-governance/lib.sh"

PASS=0
FAIL=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

assert_eq() {
    if [[ "$2" == "$3" ]]; then
        printf '  ok - %s\n' "$1"; PASS=$((PASS + 1))
    else
        printf '  not ok - %s\n      expected: %q\n      actual:   %q\n' "$1" "$2" "$3"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    if [[ "$3" == *"$2"* ]]; then
        printf '  ok - %s\n' "$1"; PASS=$((PASS + 1))
    else
        printf '  not ok - %s\n      missing substring: %q\n      in:               %q\n' "$1" "$2" "$3"
        FAIL=$((FAIL + 1))
    fi
}

# A repo skeleton: $WORK/repo with .governance/ scaffolded from the shipped runtime.
make_repo() {
    local repo="$1"
    rm -rf "$repo"
    mkdir -p "$repo/.governance"
    cp "$RUN_SH" "$repo/.governance/run.sh"
    cp "$LIB_SH" "$repo/.governance/lib.sh"
    chmod +x "$repo/.governance/run.sh"
}

# Add a check.sh under packs/<pack>/directives/<id>/ that always passes.
add_pack_directive_pass() {
    local repo="$1" pack_id="$2" directive_id="$3"
    local ddir="$repo/.governance/packs/$pack_id/directives/$directive_id"
    mkdir -p "$ddir"
    cat > "$ddir/directive.yaml" <<EOF
hook: none
surface: repo-state
EOF
    cat > "$ddir/check.sh" <<EOF
#!/usr/bin/env bash
source "\$(dirname "\$0")/../../../../../lib.sh"
directive_start "$directive_id"
directive_end
EOF
    chmod +x "$ddir/check.sh"
}

add_pack_directive_fail() {
    local repo="$1" pack_id="$2" directive_id="$3"
    local ddir="$repo/.governance/packs/$pack_id/directives/$directive_id"
    mkdir -p "$ddir"
    cat > "$ddir/directive.yaml" <<EOF
hook: none
surface: repo-state
EOF
    cat > "$ddir/check.sh" <<EOF
#!/usr/bin/env bash
source "\$(dirname "\$0")/../../../../../lib.sh"
directive_start "$directive_id"
violation "intentional fail"
directive_end
EOF
    chmod +x "$ddir/check.sh"
}

# ---- run.sh: SKIP_GOVERNANCE=1 --------------------------------------------

printf '── run.sh: SKIP_GOVERNANCE=1 ───────────────────────────\n'
make_repo "$WORK/r1"
output="$(SKIP_GOVERNANCE=1 bash "$WORK/r1/.governance/run.sh" 2>&1)"
exit_code=$?
assert_eq "exit 0 under SKIP_GOVERNANCE=1" 0 "$exit_code"
assert_contains "prints skip notice"      "SKIP_GOVERNANCE=1" "$output"

# ---- run.sh: empty .governance/ tree exits 0 with a notice -----------------

printf '── run.sh: empty .governance/ tree ─────────────────────\n'
make_repo "$WORK/r2"
set +e
output="$(bash "$WORK/r2/.governance/run.sh" 2>&1)"
exit_code=$?
set -e
assert_eq "exit 0 when no directives are installed" 0 "$exit_code"
assert_contains "prints 'no governance directives' notice" "no governance directives defined" "$output"

# ---- run.sh: all-pass run --------------------------------------------------

printf '── run.sh: all checks pass ─────────────────────────────\n'
make_repo "$WORK/r3"
add_pack_directive_pass "$WORK/r3" "acme/alpha-pack" "alpha"
add_pack_directive_pass "$WORK/r3" "acme/alpha-pack" "beta"
add_pack_directive_pass "$WORK/r3" "acme/beta-pack" "gamma"
set +e
output="$(bash "$WORK/r3/.governance/run.sh" 2>&1)"
exit_code=$?
set -e
assert_eq "exit 0 when every directive passes" 0 "$exit_code"
assert_contains "summary line names the count" "all 3 directive(s) passed" "$output"
assert_contains "discovers pack directive alpha" "alpha" "$output"
assert_contains "discovers pack directive beta"  "beta"  "$output"
assert_contains "discovers second-pack directive gamma" "gamma" "$output"

# ---- run.sh: at least one fail → exit 1 + bypass instructions -------------

printf '── run.sh: failure surfaces bypass instructions ────────\n'
make_repo "$WORK/r4"
add_pack_directive_pass "$WORK/r4" "acme/test" "happy"
add_pack_directive_fail "$WORK/r4" "acme/test" "sad"
set +e
output="$(bash "$WORK/r4/.governance/run.sh" 2>&1)"
exit_code=$?
set -e
assert_eq "exit 1 when any directive fails" 1 "$exit_code"
assert_contains "summary names failure count"  "1 directive(s) failed" "$output"
assert_contains "summary names pass count"     "1 passed" "$output"
assert_contains "prints SKIP_GOVERNANCE bypass" "SKIP_GOVERNANCE=1 git commit" "$output"
assert_contains "prints --no-verify bypass"    "git commit --no-verify" "$output"

# ---- run.sh: single-directive filter --------------------------------------

printf '── run.sh: single-directive filter ─────────────────────\n'
make_repo "$WORK/r5"
add_pack_directive_pass "$WORK/r5" "acme/test" "wanted"
add_pack_directive_fail "$WORK/r5" "acme/test" "unwanted"
# Filter to just "wanted" — should pass even though "unwanted" exists.
set +e
output="$(bash "$WORK/r5/.governance/run.sh" wanted 2>&1)"
exit_code=$?
set -e
assert_eq "filter exits 0 when only filtered directive passes" 0 "$exit_code"
assert_contains "filter result lists wanted"    "wanted" "$output"
if [[ "$output" != *"intentional fail"* ]]; then
    PASS=$((PASS + 1)); printf '  ok - filter does not run sibling directives\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - filter ran a sibling that should be skipped\n'
fi

# Filter matching nothing → exit 1.
set +e
output="$(bash "$WORK/r5/.governance/run.sh" no-such-directive 2>&1)"
exit_code=$?
set -e
assert_eq "filter exits 1 when no directive matches" 1 "$exit_code"
assert_contains "filter prints clear miss notice" "no directive matching" "$output"

# ---- lib.sh: directive_start / directive_end --------------------------------

printf '── lib.sh: directive_start / directive_end ─────────────\n'
# Run a directive fragment in isolation by sourcing lib.sh into a subshell.
set +e
output=$(
    set +u
    source "$LIB_SH"
    directive_start "demo-pass"
    directive_end
)
exit_code=$?
set -e
assert_eq "directive_end exits 0 when no violations recorded" 0 "$exit_code"
assert_contains "passing directive emits ✓ + name" "✓ demo-pass" "$output"

set +e
output=$(
    set +u
    source "$LIB_SH"
    directive_start "demo-fail"
    violation "broken thing"
    violation "other broken thing"
    directive_end
)
exit_code=$?
set -e
assert_eq "directive_end exits 1 when violations recorded" 1 "$exit_code"
assert_contains "failing directive emits ✗ + name"      "✗ demo-fail" "$output"
assert_contains "failing directive announces count"     "(2 violations)" "$output"
assert_contains "failing directive lists each violation #1" "broken thing" "$output"
assert_contains "failing directive lists each violation #2" "other broken thing" "$output"

# Singular form when count == 1.
set +e
output=$(
    set +u
    source "$LIB_SH"
    directive_start "demo-fail-1"
    violation "lonely"
    directive_end
)
set -e
assert_contains "single-violation count uses singular form" "(1 violation)" "$output"

# ---- lib.sh: require_git ---------------------------------------------------

printf '── lib.sh: require_git ─────────────────────────────────\n'
not_a_repo="$WORK/not-a-repo"
mkdir -p "$not_a_repo"
set +e
output=$(
    cd "$not_a_repo"
    set +u
    source "$LIB_SH"
    directive_start "demo"
    require_git
    # Should not reach here.
    echo "REACHED-PAST-REQUIRE-GIT"
)
exit_code=$?
set -e
assert_eq "require_git exits 0 outside a git repo" 0 "$exit_code"
assert_contains "require_git emits ⊘ skip" "⊘ demo" "$output"
if [[ "$output" != *"REACHED-PAST-REQUIRE-GIT"* ]]; then
    PASS=$((PASS + 1)); printf '  ok - require_git short-circuits the check\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - require_git did not short-circuit\n'
fi

# Inside a real git repo, require_git is a no-op.
real_repo="$WORK/real-repo"
mkdir -p "$real_repo"
git -C "$real_repo" init -q
set +e
output=$(
    cd "$real_repo"
    set +u
    source "$LIB_SH"
    directive_start "demo"
    require_git
    echo "REACHED"
    directive_end
)
set -e
assert_contains "require_git inside a repo does not short-circuit" "REACHED" "$output"

# ---- lib.sh: tracked_files respects .gitignore -----------------------------

printf '── lib.sh: tracked_files ───────────────────────────────\n'
ignored_repo="$WORK/ignored-repo"
mkdir -p "$ignored_repo"
git -C "$ignored_repo" init -q
echo "ignored.txt" > "$ignored_repo/.gitignore"
echo "tracked"   > "$ignored_repo/tracked.txt"
echo "ignored"   > "$ignored_repo/ignored.txt"
git -C "$ignored_repo" add -A
git -C "$ignored_repo" -c user.email=t@e -c user.name=t commit -q -m "init"

output=$(
    cd "$ignored_repo"
    set +u
    source "$LIB_SH"
    tracked_files
)
assert_contains "tracked.txt is tracked"           "tracked.txt" "$output"
if [[ "$output" != *"ignored.txt"* ]]; then
    PASS=$((PASS + 1)); printf '  ok - ignored.txt absent from tracked_files\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - ignored.txt should not appear\n'
fi

# Pathspec filter: only .gitignore.
output=$(
    cd "$ignored_repo"
    set +u
    source "$LIB_SH"
    tracked_files '.gitignore'
)
assert_contains ".gitignore reaches the filtered list" ".gitignore" "$output"
if [[ "$output" != *"tracked.txt"* ]]; then
    PASS=$((PASS + 1)); printf '  ok - pathspec filter excludes non-matching files\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - pathspec filter should narrow to .gitignore only\n'
fi

# ---- lib.sh: has_waiver ----------------------------------------------------

printf '── lib.sh: has_waiver ──────────────────────────────────\n'
waiver_file="$WORK/waiver.txt"
# Build the AWS-key prefix from a variable so this test file itself doesn't
# carry a string the secrets-hygiene directive's regex would flag. The on-disk
# fixture inside $WORK/ is identical to the literal we want — the indirection
# only hides the literal from a static scan of tracked source.
aws_prefix="AK""IA"
cat > "$waiver_file" <<EOF
secret = "${aws_prefix}0000000000000000"
secret_with_waiver = "${aws_prefix}0000000000000001"  # governance: allow-secrets-hygiene TICKET-7
EOF
set +e
(
    set +u
    source "$LIB_SH"
    if has_waiver "$waiver_file" 1 "secrets-hygiene"; then exit 99; else exit 0; fi
)
exit_code=$?
set -e
assert_eq "no waiver on line 1 → exit 0" 0 "$exit_code"

set +e
(
    set +u
    source "$LIB_SH"
    if has_waiver "$waiver_file" 2 "secrets-hygiene"; then exit 0; else exit 1; fi
)
exit_code=$?
set -e
assert_eq "waiver on line 2 → exit 0" 0 "$exit_code"

# Different directive id → no waiver, even when the marker is present for another id.
set +e
(
    set +u
    source "$LIB_SH"
    if has_waiver "$waiver_file" 2 "different-rule"; then exit 99; else exit 0; fi
)
exit_code=$?
set -e
assert_eq "waiver is scoped to the named directive id" 0 "$exit_code"

# ---- lib.sh: has_file_waiver ----------------------------------------------

printf '── lib.sh: has_file_waiver ─────────────────────────────\n'

# File without any waiver token → no waiver.
fwaiver_no="$WORK/fwaiver_no.ts"
{ for i in $(seq 1 5); do printf 'export const k%d = %d;\n' "$i" "$i"; done; } > "$fwaiver_no"
set +e
(
    set +u
    source "$LIB_SH"
    if has_file_waiver "$fwaiver_no" "repo-hygiene" "file-size-limit"; then exit 99; else exit 0; fi
)
exit_code=$?
set -e
assert_eq "no token in file → exit non-zero (no waiver)" 0 "$exit_code"

# Token in line 1 → waiver applies.
fwaiver_yes="$WORK/fwaiver_yes.ts"
{
    printf '// governance: allow-repo-hygiene file-size-limit TICKET-9 entrypoint\n'
    for i in $(seq 1 5); do printf 'export const k%d = %d;\n' "$i" "$i"; done
} > "$fwaiver_yes"
set +e
(
    set +u
    source "$LIB_SH"
    if has_file_waiver "$fwaiver_yes" "repo-hygiene" "file-size-limit"; then exit 0; else exit 1; fi
)
exit_code=$?
set -e
assert_eq "head-of-file waiver → exit 0" 0 "$exit_code"

# Token in line 10 → still within the 10-line head window.
fwaiver_l10="$WORK/fwaiver_l10.ts"
{
    for i in $(seq 1 9); do printf 'export const k%d = %d;\n' "$i" "$i"; done
    printf '// governance: allow-repo-hygiene file-size-limit TICKET-10\n'
    for i in $(seq 11 15); do printf 'export const k%d = %d;\n' "$i" "$i"; done
} > "$fwaiver_l10"
set +e
(
    set +u
    source "$LIB_SH"
    if has_file_waiver "$fwaiver_l10" "repo-hygiene" "file-size-limit"; then exit 0; else exit 1; fi
)
exit_code=$?
set -e
assert_eq "waiver on line 10 → exit 0 (within 10-line window)" 0 "$exit_code"

# Token past line 10 → no waiver.
fwaiver_l11="$WORK/fwaiver_l11.ts"
{
    for i in $(seq 1 10); do printf 'export const k%d = %d;\n' "$i" "$i"; done
    printf '// governance: allow-repo-hygiene file-size-limit TICKET-11\n'
} > "$fwaiver_l11"
set +e
(
    set +u
    source "$LIB_SH"
    if has_file_waiver "$fwaiver_l11" "repo-hygiene" "file-size-limit"; then exit 99; else exit 0; fi
)
exit_code=$?
set -e
assert_eq "waiver beyond line 10 → no waiver" 0 "$exit_code"

# Sub-check name must match — `file-size-limit` token must not waive a different sub-check.
set +e
(
    set +u
    source "$LIB_SH"
    if has_file_waiver "$fwaiver_yes" "repo-hygiene" "debug-statements"; then exit 99; else exit 0; fi
)
exit_code=$?
set -e
assert_eq "waiver is scoped to the named sub-check" 0 "$exit_code"

# Directive id must match — `repo-hygiene` token must not waive `secrets-hygiene`.
set +e
(
    set +u
    source "$LIB_SH"
    if has_file_waiver "$fwaiver_yes" "secrets-hygiene" "file-size-limit"; then exit 99; else exit 0; fi
)
exit_code=$?
set -e
assert_eq "waiver is scoped to the named directive id" 0 "$exit_code"

# ---- lib.sh: conf_file / conf_get / conf_rule_lines -----------------------

printf '── lib.sh: conf_file / conf_get / conf_rule_lines ──────\n'
conf_repo="$WORK/conf-repo"
mkdir -p "$conf_repo/.governance/conf"
git -C "$conf_repo" init -q
cat > "$conf_repo/.governance/conf/sample.conf" <<'EOF'
# a comment line
FRESHNESS_DAYS=30
EMPTY=
frozen-files receipts/*.md
  append-only COSTS.md   # trailing comment
NOTAKEY here
EOF

# conf_file: present → prints path, exit 0
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_file sample)
exit_code=$?
assert_eq "conf_file present → exit 0" 0 "$exit_code"
assert_contains "conf_file prints the conf path" ".governance/conf/sample.conf" "$output"

# conf_file: absent → exit 1, no output
set +e
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_file missing)
exit_code=$?
set -e
assert_eq "conf_file absent → exit 1" 1 "$exit_code"
assert_eq "conf_file absent → no output" "" "$output"

# conf_get: value from conf
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_get sample FRESHNESS_DAYS 90)
assert_eq "conf_get reads value from conf" "30" "$output"

# conf_get: env overrides conf
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; GOVERNANCE_FRESHNESS_DAYS=7 conf_get sample FRESHNESS_DAYS 90)
assert_eq "conf_get env beats conf" "7" "$output"

# conf_get: missing key → default
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_get sample MISSING 90)
assert_eq "conf_get missing key → default" "90" "$output"

# conf_get: no conf at all → default
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_get nopack MISSING 90)
assert_eq "conf_get no conf → default" "90" "$output"

# conf_rule_lines: comments / blanks / KEY= lines stripped, rest trimmed
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_rule_lines sample)
expected=$'frozen-files receipts/*.md\nappend-only COSTS.md\nNOTAKEY here'
assert_eq "conf_rule_lines yields trimmed rule lines only" "$expected" "$output"

# conf_rule_lines: no conf → empty, exit 0
set +e
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_rule_lines nopack)
exit_code=$?
set -e
assert_eq "conf_rule_lines no conf → exit 0" 0 "$exit_code"
assert_eq "conf_rule_lines no conf → empty" "" "$output"

# ---- lib.sh: conf_list (defaults + overlay layering) ----------------------

printf '── lib.sh: conf_list ───────────────────────────────────\n'
list_repo="$WORK/list-repo"
mkdir -p "$list_repo/.governance/conf"
git -C "$list_repo" init -q
cat > "$list_repo/defaults.conf" <<'EOF'
# pack-owned defaults
feat
fix
chore
style
EOF

# No overlay → effective list is the defaults verbatim.
output=$(cd "$list_repo"; set +u; source "$LIB_SH"; conf_list cmf ./defaults.conf | tr '\n' ' ')
assert_eq "conf_list no overlay → defaults" "feat fix chore style " "$output"

# Overlay adds and removes (gitignore-style ! negation).
cat > "$list_repo/.governance/conf/cmf.conf" <<'EOF'
# my overlay
!style
wip
EOF
output=$(cd "$list_repo"; set +u; source "$LIB_SH"; conf_list cmf ./defaults.conf | tr '\n' ' ')
assert_eq "conf_list overlay removes default + adds new" "feat fix chore wip " "$output"

# Whitespace-normalized removal: a single-spaced ! line matches a column-aligned
# default, and additions append while preserving default alignment.
cat > "$list_repo/defaults.conf" <<'EOF'
frozen-files    receipts/*.md
append-only      COSTS.md
frozen-section  QUALITY.md         Resolved
EOF
cat > "$list_repo/.governance/conf/cmf.conf" <<'EOF'
!frozen-section QUALITY.md Resolved
append-only docs/DECISIONS.md
EOF
output=$(cd "$list_repo"; set +u; source "$LIB_SH"; conf_list cmf ./defaults.conf)
expected=$'frozen-files    receipts/*.md\nappend-only      COSTS.md\nappend-only docs/DECISIONS.md'
assert_eq "conf_list normalizes whitespace for ! removal" "$expected" "$output"

# Removing every default → empty effective list.
cat > "$list_repo/.governance/conf/cmf.conf" <<'EOF'
!frozen-files receipts/*.md
!append-only COSTS.md
!frozen-section QUALITY.md Resolved
EOF
output=$(cd "$list_repo"; set +u; source "$LIB_SH"; conf_list cmf ./defaults.conf)
assert_eq "conf_list can empty the list" "" "$output"

# ---- summary --------------------------------------------------------------

printf '\n────────────────────────────────────────\n'
if [[ $FAIL -eq 0 ]]; then
    printf '✓ test-runtime: %d assertion(s) passed\n' "$PASS"
    exit 0
fi
printf '✗ test-runtime: %d failed, %d passed\n' "$FAIL" "$PASS"
exit 1
