---
title: "4c field type inference: method returning a field has no repr"
state: pending
urgency: normal
milestone: v0.1
created: 2026-06-26T20:20:37.882787669Z
updated: 2026-06-26T20:20:37.882787669Z
---

Localized by 4c-3 e2e (classes field-basic/field-attrs). A method that returns a field (method name { $name } or a :reader) lowers to FieldAccess, which reaches the backend with NO representation -- the field has no declared type. 4c-1a emits no field type; the backend MOP::Field requires type (LLVM.pm:452). Fix: infer field type from the initfields_cv default (Int default -> Int field) and/or from :param usage, and emit fields[].type in the classes section; the loader passes type=> to declare_field. Pairs with 4c-1b (defaults are in the same initfields_cv). Blocks field-basic, field-attrs, method-call corpus cases.
