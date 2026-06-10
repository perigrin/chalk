---
title: "Bootstrap-target migration: Chalk::Bootstrap::{Perl,BNF}::Target::* -> Chalk::Target::*"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-06-10T19:50:59.634910924Z
updated: 2026-06-10T19:50:59.634910924Z
---

The full ~153-consumer migration of the Bootstrap-namespaced targets (Perl/C/XS + the BNF/XS AST tree + EmitHelpers/ClassRegistry) into Chalk::Target::*, sequenced WITH the broader Bootstrap->Chalk rename, not ahead of it. The reconciliation plan (2026-06-08, namespace section ~447) claimed this was filed as a separate rename-tied issue — it never was (whole-branch review 2026-06-10 caught the unfiled deferral). The narrow move (Chalk::Target base + Chalk::Target::LLVM) is DONE (R1); this is the big half.
