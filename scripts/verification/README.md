# Pinned quasi-Riemann verification

This workflow tests only `OAI.riemannZeta_ne_zero_of_seven_eighths_lt_re`
at math commit `adc7f1241b42e322a6451854ab7e4b4c146bf78a`:
`(7 / 8 : ℝ) < s.re → riemannZeta s ≠ 0`.
It does **not** prove the full Riemann hypothesis or establish usefulness to Daedalus.
No proof sources, main-branch files, or Daedalus files are changed by a run.

## Verification sequence

1. Fetch the exact source and tool commits listed in `quasi-riemann.sh`.
2. Download the exact official Lean 4.34.1 release and log its observed SHA-256.
   That hash is provenance, not verification against an independently trusted checksum.
3. Build comparator and its manifest-pinned exporter with Lean 4.34.1.
   Both tools originally target 4.34.0; successful compilation on 4.34.1 is required,
   not assumed. Build Landrun from its pinned source with the runner's Go toolchain.
4. Use the minimal checked-in Lake configuration in the temporary project only.
   It retains Mathlib, PrimeNumberTheoremAnd and rellich-kondrachov pins needed
   by the screened import closure. Apply the pinned repository's two compatibility
   patches, and download trusted Mathlib caches. No OAI solution is precompiled.
5. Fail closed unless an unprivileged systemd service has Landlock ABI ≥4 and
   AF_UNIX sockets disabled. Empty capabilities and NoNewPrivileges are required.
6. Let comparator build and export the challenge before building and exporting
   the solution, compare declarations and permitted axioms, then replay the
   exported solution in Lean's kernel. Nanoda is disabled by the pinned challenge.

## Evidence and interpretation

Artifacts retain runner/tool/dependency/compiler/comparator logs, pins, the
resolved dependency manifest, challenge JSON, temporary config diff and result.
The script reports its last phase and exit code. A failed, canceled, timed-out,
out-of-memory or infrastructure-blocked run is **not verified**, not a theorem
disproof. Only `phase=comparator-passed` with exit code zero means this comparator
run passed. GitHub's own run/job status remains authoritative for completion.
Artifacts expire after 30 days; retain them separately before claiming durable evidence.

Trust assumptions include the official release download, trusted challenge and
its imports, minimal Lake/dependency configurations and compatibility patches,
Mathlib cache, pinned tooling, Lean kernel, operating system and hardware.
Landrun's upstream comparator invocation uses `--best-effort`; the ABI preflight
and systemd socket restriction are mandatory guards, not optional workarounds.
This is not independent-kernel certification or a substitute for human review
of the statement's mathematical meaning.

The workflow is draft infrastructure until a real CI run succeeds. Hosted-runner
memory, build duration and dependency compatibility may require further work.
It uses read-only GitHub permissions, no persisted checkout credentials, no
secrets, no `pull_request_target`, no privileged proof process and no sandbox bypass.
