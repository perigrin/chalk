---
title: LLVM backend reads the MOP directly (retire the ClassInfo bridge)
state: pending
urgency: normal
milestone: codegen-harness
blocks:
- 019eb421-1401-78e6-8734-a7983effaf73
- 019eaa51-c46a-71ee-86e1-2cb5b85dbf57
created: 2026-06-11T00:52:25.803634304Z
updated: 2026-06-11T12:26:05.270824808Z
---

Architecture-review resolution 2026-06-11 (docs/plans/2026-06-11-target-ir-architecture-review-resolution.md): the metadata structs delete eventually; the LLVM backend should read MOP::Class/Method/Field/Phaser::Adjust directly (the Perl target proves MOP-driven emission). R3 ClassInfo consumption (_populate_registry_from_classinfo, MethodInfo.body_node/return_repr) is TRANSITIONAL.

DESIGN QUESTIONS owned by this issue (named in the resolution):
1. The node-input protocol: hash-consing requires id() + add_consumer on anything riding as a node input — R3 picked the immutable structs for exactly this. Either (a) MOP metaobjects gain the protocol (content-based id(), no-op add_consumer), or (b) class structure moves OFF the node-input channel (e.g. a registry handed to the backend alongside the graph — lower_with_elaboration already threads class_registry).
2. The corpus contract shape follows: classes.md/host.md ir-blocks build ClassInfo(...)/MethodInfo(...) as the parser-spec shape; the harness builder + ir-block vocabulary migrate with the backend (likely MOP::Class via declare_* in the harness), and the corpus dual-contract docs amend.
3. The method-body lowering inputs (body_node/return_repr) map onto MOP::Method (graph/return_type) or equivalents.

Blocks MOP-migration 4/4 (struct deletion) — wired. Independent of the Target::C chain head (different backend).
