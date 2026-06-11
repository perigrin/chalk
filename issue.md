---
title: "MOP migration 2/4: delete the legacy Perl path + cfg_state() read adapter"
state: pending
urgency: normal
milestone: codegen-harness
blocked_by:
- 019eb420-b5c1-7cc7-a3f8-cfaa68af7df0
blocks:
- 019eb421-13e9-7411-b8e9-cab95da31177
created: 2026-06-11T00:42:07.182306814Z
updated: 2026-06-11T00:43:13.046161452Z
---

Item 2 of the re-audit punch list (blocked by 1/4): with Target::C migrated, delete the Perl legacy path (_emit_program, _generate_with_cfg) and the Context::cfg_state() read-only adapter (Context.pm:205) + migrate its codegen and 22 test-file consumers.
