---
title: "4c field type inference: method returning a field has no repr"
state: pending
urgency: normal
milestone: v0.1
created: 2026-06-26T20:20:37.882787669Z
updated: 2026-06-28T20:59:38.603523476Z
---

Localized by 4c-3/4c-1b e2e (classes field-basic, field-attrs, adjust, method-call). After 4c-1b, fields with a CONSTANT DEFAULT get a type (Int/Num/Str from the default) and the loader stamps FieldAccess reprs + propagates computed reprs -- so a field-write body lowers. REMAINING field-type cases:

(1) BARE :param field, no default (field $name :param; method name {$name}): the type is the constructor ARGUMENT type (new(name=>cat) => Str). Needs call-site type inference: flow the Call(new) param value types to the field types. Blocks field-basic, field-attrs.

(2) Field typed only by an ADJUST WRITE (field $double; ADJUST { $double = $val*2 }): the type is the ADJUST assignment RHS type (Int). Needs inferring field types from ADJUST/method field-writes. Blocks adjust.

Both are field-type SOURCES the class declaration alone does not carry. The repr machinery (stamp FieldAccess from field type, propagate computed reprs) is DONE in 4c-1b (Serialize/JSON _stamp_field_access_reprs + _propagate_computed_reprs); this issue is now ONLY the type-SOURCE inference for non-default fields.

SEPARATE: object-state mutation across method calls -- method-call ($c->inc; $c->val) lowers but returns the default (0) not 11; field state must persist across calls. That is an object-state/lowering issue, not field typing -- track separately if not already.
