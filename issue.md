---
title: "Phase 4 stage 4d: regex/host tier (regex.md + host.md through B::SoN)"
state: pending
urgency: normal
milestone: codegen-harness
blocked_by:
- 019f1bd2-dca7-7a1a-8d9e-76b666eae7b9
created: 2026-07-01T04:19:29.835915202Z
updated: 2026-07-01T04:19:42.362490822Z
---

Phase 4 stage 4d -- the regex/host tier (brief stage list). Named Phase-4 stage that currently exists only as scattered fast-follows, not a tracked stage. From the corpus-wide map: regex 0/6 green, host 0/3 green.

Scope: B::SoN produces + Chalk lowers the regex.md and host.md corpus sources.
- regex: RegexMatch repr seeded (RC1 done) but match-as-conditional hits RC5 (ternary Str/Int typing); s/// R3 miscompiles (RC4); qr// dies in the producer (RC3). So 4d regex is largely BLOCKED-BY RC3/RC4/RC5.
- host: $1 capture (RC3 producer-dies), %ENV read (EnvRead not modeled -- Subscript on Str repr). Maps to the G7 host contract (RegexCapture $N, EnvRead).
This stage issue tracks 4d as a whole and depends on RC3/RC4/RC5 + the G7 host model (31e7). Filed so the named stage is not lost.
