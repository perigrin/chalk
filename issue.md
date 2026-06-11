---
title: "MOP migration 2/4: delete the legacy Perl path + cfg_state() read adapter"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-06-11T00:42:07.182306814Z
updated: 2026-06-11T00:42:07.182306814Z
---

Item 2 of the re-audit punch list (blocked by 1/4): with Target::C migrated, delete the Perl legacy path (_emit_program, _generate_with_cfg) and the Context::cfg_state() read-only adapter (Context.pm:205) + migrate its codegen and 22 test-file consumers.
