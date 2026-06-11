---
title: "MOP migration 1/4: Target::C entry-point onto the schedule-driven MOP path"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-06-11T00:41:43.105256279Z
updated: 2026-06-11T00:41:43.105256279Z
---

Item 1 of the re-audit punch list (docs/plans/2026-06-10-mop-migration-reaudit.md s5) — the NEW highest-leverage single unblock for the stalled SoN-IR/MOP migration (~2/3 complete per the re-audit).

Make Target::C generate($mop) REAL (it is a stub, C.pm:1721-1726) by routing the existing schedule-driven emission through it; retire _generate_c_files($ir,$sa,$ctx), the EmitHelpers $_sa/$_ctx backchannel, and the chalk.so build script backchannel call. The Perl target already proves the schedule-driven MOP path at golden parity. Target::C is the LAST load-bearing consumer keeping alive: the ($sa,$ctx) backchannel (the same literal-moved-contract-didnt pattern compat_class had), Context::cfg_state(), the legacy Perl path, and the body dual-write.

GATE: sequencing is contingent on the target/IR architecture review LLVM-first-vs-C/XS-first standing decision (2026-06-06 three-axis doc defers C/XS near capstone) — if LLVM-first holds, items 2-4 may reorder around the LLVM backend ClassInfo consumption instead. Decide deliberately before starting.
