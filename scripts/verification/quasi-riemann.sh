#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

SOURCE_SHA=adc7f1241b42e322a6451854ab7e4b4c146bf78a
COMPARATOR_SHA=d03acab154d269c06e60e4de7e4cc85deebff94b
EXPORT_SHA=076e8e57707e813375e8f9da8bf989799ace9680
LANDRUN_SHA=811cfff51ceaf3d9843708aa6d22e9b84ccac8b4
LEAN_VERSION=4.34.1
root=$(pwd)
evidence="$root/verification-evidence"
mkdir -p "$evidence"
phase=setup
finish() {
  rc=$?
  printf 'phase=%s\nexit_code=%s\n' "$phase" "$rc" > "$evidence/result.txt"
}
trap finish EXIT
exec > >(tee "$evidence/runner.log") 2>&1

work=$(mktemp -d /var/tmp/quasi-riemann.XXXXXXXX)
printf 'source=%s\ncomparator=%s\nlean4export=%s\nlandrun=%s\nlean=%s\n' \
  "$SOURCE_SHA" "$COMPARATOR_SHA" "$EXPORT_SHA" "$LANDRUN_SHA" "$LEAN_VERSION" \
  > "$evidence/pins.txt"
uname -a
df -h
free -h

fetch_commit() {
  local url=$1 sha=$2 target=$3
  git init "$target"
  git -C "$target" remote add origin "$url"
  git -C "$target" fetch --depth=1 origin "$sha"
  git -C "$target" checkout --detach FETCH_HEAD
  test "$(git -C "$target" rev-parse HEAD)" = "$sha"
}
fetch_commit https://github.com/VentureStratosphereWorldwide/math.git "$SOURCE_SHA" "$work/source"
fetch_commit https://github.com/leanprover/comparator.git "$COMPARATOR_SHA" "$work/comparator"
fetch_commit https://github.com/Zouuup/landrun.git "$LANDRUN_SHA" "$work/landrun"

# Download the official exact Lean release, not an unpinned installer script.
curl --fail --location --retry 3 \
  "https://github.com/leanprover/lean4/releases/download/v${LEAN_VERSION}/lean-${LEAN_VERSION}-linux.tar.zst" \
  -o "$work/lean.tar.zst"
sha256sum "$work/lean.tar.zst" > "$evidence/lean-download.sha256"
tar --zstd -xf "$work/lean.tar.zst" -C "$work"
export PATH="$work/lean-${LEAN_VERSION}-linux/bin:$PATH"
lean --version
lake --version

# Comparator's checked-in manifest pins the compatible exporter. Never lake update here.
python3 - "$work/comparator/lake-manifest.json" "$EXPORT_SHA" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))['packages']
assert len(p) == 1 and p[0]['name'] == 'lean4export'
assert p[0]['rev'] == sys.argv[2]
PY
(
  cd "$work/comparator"
  lake build lean4export comparator
  test "$(git -C .lake/packages/lean4export rev-parse HEAD)" = "$EXPORT_SHA"
) 2>&1 | tee "$evidence/tool-build.log"
(
  cd "$work/landrun"
  go version
  GOTOOLCHAIN=auto go build -mod=readonly -o "$work/landrun-bin" cmd/landrun/main.go
)

# Only the temporary verification project's Lake configuration is replaced.
# This avoids loading dozens of unrelated dependency configurations.
cp scripts/verification/lakefile.lean "$work/source/lean/lakefile.lean"
git -C "$work/source" diff -- lean/lakefile.lean > "$evidence/project-config.diff"
cp "$work/source/lean/ComparatorChallenges/QuasiRiemannHypothesis.json" "$evidence/challenge.json"
cp "$work/source/lean/lean-toolchain" "$evidence/lean-toolchain"

# No sudo-enabled runner identity enters the verification process.
sudo useradd --system --create-home --home-dir "$work/home" --shell /bin/bash proofcheck
sudo chown -R proofcheck:proofcheck "$work/source" "$work/home"
chmod 755 "$work"
verify_path="$work/lean-${LEAN_VERSION}-linux/bin:/usr/local/bin:/usr/bin:/bin"
service() {
  sudo systemd-run --quiet --wait --pipe --collect \
    --property=User=proofcheck --property=Group=proofcheck \
    --property=NoNewPrivileges=yes --property=CapabilityBoundingSet= \
    --property='RestrictAddressFamilies=~AF_UNIX' \
    --property="WorkingDirectory=$work/source/lean" \
    --setenv="HOME=$work/home" --setenv="PATH=$verify_path" \
    --setenv="COMPARATOR_LANDRUN=$work/landrun-bin" \
    --setenv="COMPARATOR_LEAN4EXPORT=$work/comparator/.lake/packages/lean4export/.lake/build/bin/lean4export" \
    "$@"
}
phase=sandbox-preflight
service /usr/bin/python3 -c '
import ctypes, os, platform, socket
assert os.geteuid() != 0 and set(os.getgroups()) <= {os.getegid()}, "privileged identity"
assert platform.machine() == "x86_64"
abi = ctypes.CDLL(None, use_errno=True).syscall(444, 0, 0, 1)
assert abi >= 4, f"Landlock ABI {abi}: sandbox unavailable or too old"
try:
    socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
except OSError:
    pass
else:
    raise RuntimeError("AF_UNIX restriction not active")
print(f"Sandbox preflight passed; Landlock ABI {abi}")
'

phase=dependency-setup
service /bin/bash -euo pipefail -c '
lake update
for dependency in PrimeNumberTheoremAnd rellich-kondrachov; do
  git -C ".lake/packages/$dependency" apply --check "$PWD/patches/$dependency-lean4341.patch"
  git -C ".lake/packages/$dependency" apply "$PWD/patches/$dependency-lean4341.patch"
done
lake exe cache get
' 2>&1 | tee "$evidence/dependency-setup.log"
cp "$work/source/lean/lake-manifest.json" "$evidence/project-manifest.json"
# Sources and challenge remain immutable; only .lake is writable to the checker.
sudo chown -R root:root "$work/source"
sudo chown -R proofcheck:proofcheck "$work/source/lean/.lake"
git -C "$work/source" -c safe.directory="$work/source" diff --exit-code -- '*.lean' \
  ':!lean/lakefile.lean'

phase=comparator
# First proof compilation occurs inside comparator, after challenge export.
service "$work/lean-${LEAN_VERSION}-linux/bin/lake" env \
  "$work/comparator/.lake/build/bin/comparator" \
  ComparatorChallenges/QuasiRiemannHypothesis.json \
  2>&1 | tee "$evidence/comparator.log"
grep -Fqx 'Lean default kernel accepts the solution' "$evidence/comparator.log"
grep -Fqx 'Your solution is okay!' "$evidence/comparator.log"
phase=comparator-passed
printf '%s\n' 'Pinned 7/8 challenge comparison and Lean kernel replay passed.' \
  'This is not full RH, human mathematical review, or independent-kernel verification.'
