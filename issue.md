---
title: _finalize_body_graph dissolution (lateral-bindings campaign scope)
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-06-11T00:42:07.259112749Z
updated: 2026-06-11T00:42:07.259112749Z
---

Re-audit punch-list item 5c: _finalize_body_graph (Actions.pm ~1010+) is the residue of the deleted _build_method_graph — a post-hoc Context-subtree walker doing schedule-annotation collection, implicit-Return synthesis, and transitive cache seeding. The amended MOP plan says this aggregation should not exist; the in-flight lateral-bindings/clean-control campaign OWNS control-chain construction now and is the natural home for dissolving it (see memory ir_construction_during_parse_option_a: during-parse lateral control threading makes the Block rebuild retireable). Known gaps riding with it: M7 foreach-iterator TODO (ir-completeness.t 315/316).
