---
title: "RC2: control-flow + logical lower but crash at runtime (Phase 4, 8 cases)"
state: in-progress
urgency: normal
milestone: codegen-harness
created: 2026-07-01T03:57:11.648124386Z
updated: 2026-07-01T04:49:42.41147947Z
sessions:
- start_sha: b725af3d23422f1fe1384f67082be32ff7420c98
  end_sha: ""
  commits: 0
  started_at: 2026-07-01T04:49:42.41147947Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-07-01T04:49:42.41147947Z
---

Phase 4 corpus-wide root cause RC2 (8 cases). See docs/plans/2026-07-01-phase4-corpus-wide-status.md.

Control-flow and logical idioms LOWER but the emitted LLVM IR crashes at run time ("lli exited 1"):
- control-flow D2/D3/D4/D5: while, foreach, postfix-if, postfix-while.
- logical L1/L2/L4: and, or, not.

Not a type/repr gap (the IR emits) -- a control-flow / short-circuit LOWERING bug in the B::SoN -> backend path: the branch/loop structure or the merge is malformed such that lli faults at runtime. Investigate the emitted .ll for one while and one and/or to localize (missing block terminator, bad phi, wrong branch target, or a Region/Loop merge that B::SoN builds differently than Chalks parser). Closing RC2 unblocks control-flow + most of logical.
