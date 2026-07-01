---
title: "RC1: repr-inference for Subscript/RegexMatch/field nodes (Phase 4, ~15 cases)"
state: done
urgency: normal
milestone: codegen-harness
blocks:
- 019f1bda-4212-713b-9e01-3a96ad850d7e
created: 2026-07-01T03:56:57.313868946Z
updated: 2026-07-01T04:18:41.554927133Z
sessions:
- start_sha: b725af3d23422f1fe1384f67082be32ff7420c98
  end_sha: b725af3d23422f1fe1384f67082be32ff7420c98
  commits: 0
  started_at: 2026-07-01T04:18:27.848321641Z
  ended_at: 2026-07-01T04:18:27.926005461Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-07-01T04:18:27.848321641Z
- state: done
  actor: human:git-zhi
  timestamp: 2026-07-01T04:18:27.926005461Z
---

Phase 4 corpus-wide root cause RC1. See docs/plans/2026-07-01-phase4-corpus-wide-status.md.

REPR-INFERENCE PASS LANDED (Chalk b725af3d): from_json now runs a universal repr pass (_seed_and_propagate_reprs) for EVERY graph -- seeds ArrayRef->ArrayRef, HashRef->HashRef, RegexMatch->Bool; Subscript repr = container element type. Corpus-wide 24->26 GREEN: references R2 (array elem read) + R3 (hash elem read) now lower e2e.

RESIDUALS (the original ~15 estimate over-counted -- several were DIFFERENT root causes, now split out):
- CLOSED by RC1: R2, R3 (direct-aggregate element reads).
- R4/R5/R8 anon-ref deref (my $r=[1,2,3]; $r->[0]): NOT repr -- a PRODUCER binding gap. The container ArrayRef is LOST; $r reads a bare PadAccess with no value. B::SoN does not bind $r to Ref(ArrayRef(...)) through the deref. Needs a producer anon-ref-binding fix (FromOptree). SPLIT: file/track as producer work.
- R9/R10 (OOB array / missing hash key): now lower but return Int:0 not Undef: -- SEMANTICS (should be undef). Distinct from repr. -> RC4-adjacent (silent-wrong).
- regex R1/R4/R5/R6: RegexMatch->Bool seeding worked; now blocked on RC5 (TernaryExpr Str/Int branch typing). -> RC5.
- 019f0597 field-type-source (bare :param / ADJUST-written fields) still open -- the field slice of RC1 that needs a TYPE SOURCE, not just propagation.
- R1 scalar count / A5 etc.: separate (Length/return-of-ArrayRef).

RC1 repr-inference goal MET. Remaining RC1-labeled cases are: field-type-source (019f0597) + anon-ref producer binding (to file). Everything else re-homed to RC4/RC5.
