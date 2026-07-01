---
title: 4c object-state mutation across method calls
state: cancelled
urgency: normal
milestone: v0.1
created: 2026-06-28T20:59:38.722706246Z
updated: 2026-07-01T04:19:09.159299958Z
---

Localized by 4c-1b e2e (classes method-call). Counter->new(n=>10); $c->inc; $c->val LOWERS (after 4c-1b field typing) but returns the default/initial value, not the post-mutation value (got Int:0, want Int:11). The field state set by the constructor + mutated by $c->inc must persist into $c->val -- i.e. the object instance state across separate method-call statements. This is an object-lifetime/state lowering concern in the B::SoN->backend path (the three driver statements share one object), distinct from field TYPING (019f0597). Blocks method-call corpus case end-to-end.
