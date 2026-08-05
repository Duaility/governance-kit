#!/usr/bin/env bash
set -u
EVAL_ID="managed-tree-integrity"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/kit/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT" >&2; exit 1; }
source "$ROOT/kit/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/foundation"
CHECK=".governance/packs/governance-kit/foundation/directives/$EVAL_ID/check.sh"
LIBDIR=".governance/packs/governance-kit/foundation/directives/$EVAL_ID/lib"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# Compute digests with the directive's OWN routines so the recorded values are
# correct by construction (the same code the check recomputes).
source "$LIBDIR/digest.sh"
dir_digest()  { mti_dir_digest "$1"; }
file_digest() { mti_sha256_file "$1"; }

# A vendored pack folder to verify.
VPACK=".governance/packs/acme/widgets/directives/foo"
mkdir -p "$VPACK"
printf '#!/usr/bin/env bash\necho ok\n' > "$VPACK/check.sh"
printf 'summary: demo\n' > "$VPACK/directive.yaml"

write_lock() {  # $1 = digest line(s) for foo, or "  digest: {}" / empty for legacy
    {
        printf "version: '2'\npacks:\n"
        printf -- "- id: acme/widgets\n  version: '0.1'\n  source: gh\n  directives:\n  - foo\n"
        [[ -n "$1" ]] && printf '%s\n' "$1"
    } > .governance/packs.lock
}
# The fixture's lib.sh is copied from the kit assets, so its stamped marker
# tracks whatever kit version this checkout is at. Derive the manifest's
# kit_version from that marker rather than hardcoding it, or a kit release bump
# (which re-stamps the marker) would make the marker-vs-manifest check fire and
# break the "match" case in this eval.
KIT_VER="$(sed -nE 's/.*kit-version=([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' .governance/lib.sh | head -1)"
write_manifest() {  # $1 = managed_digests body, or "" to omit the block
    {
        printf 'version: "3"\nowner: acme\nrepo: widgets\nkit_version: "%s"\ntests_dir: .governance\n' "$KIT_VER"
        [[ -n "$1" ]] && printf '%s\n' "$1"
    } > .governance/install.yaml
}

FOO_D="$(dir_digest "$VPACK")"
LIB_D="$(file_digest ".governance/lib.sh")"

# 1. pass — recorded digests match disk (pack folder + runtime lib.sh)
write_lock "  digest:
    foo: $FOO_D"
write_manifest "managed_digests:
  .governance/lib.sh: $LIB_D"
EVAL_LABEL="$EVAL_ID match" expect_pass "$CHECK"

# 1b. fail — manifest kit_version disagrees with lib.sh's stamped marker, even
#     though digests still match (subsumes the former kit-version-sync check).
{
    printf 'version: "3"\nowner: acme\nrepo: widgets\nkit_version: "9.9.9"\ntests_dir: .governance\n'
    printf 'managed_digests:\n  .governance/lib.sh: %s\n' "$LIB_D"
} > .governance/install.yaml
EVAL_LABEL="$EVAL_ID marker vs manifest" expect_fail "$CHECK"
write_manifest "managed_digests:
  .governance/lib.sh: $LIB_D"   # reset kit_version to the marker's version

# 2. fail — vendored pack file modified after digest recorded
printf '\n# tampered\n' >> "$VPACK/check.sh"
EVAL_LABEL="$EVAL_ID modified pack file" expect_fail "$CHECK"

# restore exact original bytes and re-record → passes again
printf '#!/usr/bin/env bash\necho ok\n' > "$VPACK/check.sh"
write_lock "  digest:
    foo: $(dir_digest "$VPACK")"
EVAL_LABEL="$EVAL_ID restored" expect_pass "$CHECK"

# 3. fail — a recorded directive folder deleted
rm -rf "$VPACK"
EVAL_LABEL="$EVAL_ID deleted folder" expect_fail "$CHECK"
mkdir -p "$VPACK"
printf '#!/usr/bin/env bash\necho ok\n' > "$VPACK/check.sh"
printf 'summary: demo\n' > "$VPACK/directive.yaml"
write_lock "  digest:
    foo: $(dir_digest "$VPACK")"
EVAL_LABEL="$EVAL_ID re-added" expect_pass "$CHECK"

# 4. fail — an unrecorded directive folder appears under a digested pack
mkdir -p ".governance/packs/acme/widgets/directives/sneaky"
printf 'x\n' > ".governance/packs/acme/widgets/directives/sneaky/check.sh"
EVAL_LABEL="$EVAL_ID orphan directive" expect_fail "$CHECK"
rm -rf ".governance/packs/acme/widgets/directives/sneaky"

# 5. fail — a kit-runtime managed file hand-edited
printf '\n# tampered runtime\n' >> .governance/lib.sh
EVAL_LABEL="$EVAL_ID modified runtime" expect_fail "$CHECK"
# (leave lib.sh tampered; remaining cases override the manifest/waiver)

# 6. pass — legacy entry with no digest, and manifest with no managed_digests
write_lock ""
write_manifest ""
EVAL_LABEL="$EVAL_ID legacy no-digest skipped" expect_pass "$CHECK"

# 7. pass — drifted runtime file waived via the conf overlay
write_manifest "managed_digests:
  .governance/lib.sh: $LIB_D"   # lib.sh is still tampered → would fail…
mkdir -p .governance/conf/governance-kit/foundation
printf '.governance/lib.sh\n' > .governance/conf/governance-kit/foundation/$EVAL_ID.conf
EVAL_LABEL="$EVAL_ID waiver" expect_pass "$CHECK"
rm -f .governance/conf/governance-kit/foundation/$EVAL_ID.conf

# 8. issue #259 — the vendored at-rest sweep driver is a first-class managed
#    runtime file (harness-pegged bash per #355). A manifest naming only
#    `.governance/sweep.sh` isolates this case from the (still-tampered) lib.sh
#    above: a registered sweep driver that matches its recorded digest passes,
#    a hand-edit fails offline, and a conf-overlay waiver still lets it through.
printf '#!/usr/bin/env bash\n# governance-kit:managed kit-version=%s\necho sweep\n' "$KIT_VER" > .governance/sweep.sh
SWEEP_D="$(file_digest ".governance/sweep.sh")"
write_manifest "managed_digests:
  .governance/sweep.sh: $SWEEP_D"
EVAL_LABEL="$EVAL_ID sweep driver match" expect_pass "$CHECK"

# 8a. fail — sweep driver hand-edited after its digest was recorded
printf '\n# tampered sweep driver\n' >> .governance/sweep.sh
EVAL_LABEL="$EVAL_ID sweep driver modified" expect_fail "$CHECK"

# 8b. pass — drifted sweep driver waived via the conf overlay
mkdir -p .governance/conf/governance-kit/foundation
printf '.governance/sweep.sh\n' > .governance/conf/governance-kit/foundation/$EVAL_ID.conf
EVAL_LABEL="$EVAL_ID sweep driver waiver" expect_pass "$CHECK"
rm -f .governance/conf/governance-kit/foundation/$EVAL_ID.conf

# 8c. issue #263 — a sweep asset carries its *seed-time* marker and is never
#     re-stamped on a kit update, so its `kit-version=` legitimately differs from
#     the manifest pin. That divergence must NOT be a violation (unlike a true
#     runtime file, cf. case 1b): the digest still guards the content. Stamp the
#     driver with an older marker than the pin, record its matching digest →
#     passes on digest alone, no marker-vs-manifest false positive.
printf '#!/usr/bin/env bash\n# governance-kit:managed kit-version=0.0.1\necho sweep\n' > .governance/sweep.sh
write_manifest "managed_digests:
  .governance/sweep.sh: $(file_digest ".governance/sweep.sh")"
EVAL_LABEL="$EVAL_ID sweep driver seed-time marker" expect_pass "$CHECK"

# 8d. fail — the digest still guards the sweep driver even when its marker
#     diverges from the pin: a content hand-edit is caught.
printf '\n# tampered\n' >> .governance/sweep.sh
EVAL_LABEL="$EVAL_ID sweep driver divergent marker + tamper" expect_fail "$CHECK"

eval_done
