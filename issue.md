---
title: "MOP migration 3/4: retire the body dual-write + ship rewrite_mop"
state: pending
urgency: normal
milestone: codegen-harness
blocked_by:
- 019eb421-13ce-7811-b246-f17fac4fe338
created: 2026-06-11T00:42:07.209867414Z
updated: 2026-06-11T00:42:28.614293627Z
---

Item 3 of the re-audit punch list (blocked by 2/4): drop the body arrayrefs from MethodInfo/ClassInfo/SubInfo AND MOP::Method/MOP::Sub (the surface GREW during the migration — the new MOP classes copied the field); switch StructPromotion MOP path from analyze-only to graph/schedule walks per its own comment plan (StructPromotion.pm:48-50); ship rewrite_mop (the previously-UNFILED deferral). 15 ->body reader sites remain (classified in re-audit s4.3). Also the smaller contract items: DCE run($graph,$factory) -> the Pass run($X)->$X shape; decide build-or-drop for the never-built MOP::Class::all_nodes() (Phase 7 scope item, never re-deferred).
