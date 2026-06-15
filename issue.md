---
title: "4b-5: CompoundAssign in FromOptree"
state: pending
urgency: normal
milestone: v0.1
created: 2026-06-15T22:14:45.917333192Z
updated: 2026-06-15T22:14:45.917333192Z
---

Producer-side. += / .= map to Call/branch not the CompoundAssign node (4a, OpMap:70-77/153-155). Emit CompoundAssign. Unblocks variables C2, strings S4. Scope: docs/plans/2026-06-15-phase4b-scope.md
