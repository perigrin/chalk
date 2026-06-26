---
title: "4c inherited method dispatch: Call-repr + vtable through the MRO"
state: pending
urgency: normal
milestone: v0.1
created: 2026-06-26T20:20:45.542859246Z
updated: 2026-06-26T20:20:45.542859246Z
---

Localized by 4c-3 e2e (classes class-isa). $c->kind where kind is inherited from a parent (Child :isa(Base), kind on Base). The Call-repr stamping (_stamp_method_call_reprs in Serialize/JSON.pm) keys by the static class_name (Child) but kind lives on Base, so no repr is found and the Call reaches the backend with no repr. Fix: resolve method lookup through the MRO (walk parent classes) when stamping the Call repr AND in the backend vtable lookup. Blocks class-isa corpus case.
