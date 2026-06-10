---
title: "G7 fast-follows: @ARGV/$0, $!, IO-config vars, env writes, $N/env undef faces, $&"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-06-10T09:22:33.574897432Z
updated: 2026-06-10T09:22:33.574897432Z
---

Tracked follow-ups deferred from G7 (core = RegexCapture + EnvRead shipped 2026-06-10; host.md H1-H3 GREEN). Census-grounded deferral: ALL of these have ZERO uses in lib/ (the self-host target) — scripts use some, lib/ does not.

- @ARGV / $0: argv plumbing (main(argc,argv) threading into the graph; needs a graph-entry contract for process args).
- $!: errno (Num face) + strerror (Str face) — a DualVar rep; needs FAILING-SYSCALL ops the slice does not have (no open/read modelled). Do alongside the I/O cluster. See coercion_cache_dualvar_foundation memory.
- I/O config vars ($/ $\ $,): the boundary doc open question — values-consumed-by-IO-nodes (RF) vs local-dynamic globals (OOS); decide when I/O is tackled.
- env WRITES (setenv) + local %ENV.
- The UNDEF faces: a missing $ENV{key} reads as the empty string today (perl: undef); a failed-match $N reads as the empty view at offset 0 (perl: undef). Both compose with the L3 Undef tagged-scalar rep ({defined,payload}) — model when the consuming idioms (// on env reads, unguarded $N) appear in the corpus. The dominant lib/ idiom guards $N behind the match, so this is latent.
- $& / $` / $+ (group-0 + pre/post-match views): the matcher already records m0s/m0e; exposing them is mechanical when needed ($& has a perl-wide perf folklore; near-zero lib/ usage).
