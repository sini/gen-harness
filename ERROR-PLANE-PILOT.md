# Error-plane resource pilot

The runner retains every listed cell, one fresh evaluator process per cell,
existing message matching, and the pinned evaluator selected by the check.
The required check and all evaluator columns remain in place.

Worker allocation now honors `NIX_BUILD_CORES` inside the build sandbox rather
than always spawning one process per host CPU. Zero retains all available CPUs.
Linux CPU affinity bounds the allocation. For a direct runner invocation,
`GEN_ERROR_JOBS` is a positive explicit process budget; it overrides
`NIX_BUILD_CORES`. Neither variable removes cells. Invalid settings refuse with
exit 2. A process killed by a signal fails the cell, never satisfies an empty
expected-error message.

The runner prints its chosen worker count, cell count, cell-phase wall time,
sum of per-cell wall times and slowest cell to stderr. These are timings, not
RSS measurements or proof of a faster run. Version/listing time is excluded.
No memory limit is guessed from physical host RAM. This is a process-count
budget, not a memory cap; no peak RSS has been measured. Timeout and
process-group cancellation are not implemented; evaluator calls remain unbounded. Budget concurrent builds
at the host level before choosing per-build cores: multiple builders multiply
this process allocation.

Run standalone controls with `python3 error-plane-runner-test.py`; the same
controls run inside the existing tests-error derivation before the real cells.
They compare serial and parallel case membership, results and console verdicts,
and include simulated false/mismatched-message/signal controls (mocked subprocess results). They do not replace
real evaluator validation.

Before adoption, run the old and new harness against an identical written
consumer lock, each under Nix, Lix and Determinate, at worker allocations 1, 2
and 4. Retain exact evaluator identity, case paths, verdicts, complete logs,
wall time and externally measured peak RSS. Compare every case and aggregate
result; include injected expected/value failures and killed-process controls.
Use the lowest-memory allocation meeting the measured latency target. Do not
claim a minutes-scale full relock from these runner-only measurements.

Local validation for this patch: eight Python controls passed. A separate
synthetic executable control launched eight distinct evaluator PIDs for eight
unique cells and observed peak concurrency two at `GEN_ERROR_JOBS=2`. This
exercises real subprocess scheduling, not Nix evaluation or real signal handling. Nix is absent
in the editing environment, so the aggregate Nix gates, formatter and real
three-evaluator workload have not been run. This is an isolated pilot, not an
approved consumer pin or merge.
