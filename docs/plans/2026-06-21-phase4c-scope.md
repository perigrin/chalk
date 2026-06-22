# Phase 4c — The Class Tier (MOP Emission): Scope

**Date:** 2026-06-21
**Stage:** Phase 4, Stage 4c (class/MOP tier)
**Decided by:** 4a decision (b) — declarative class-structure JSON replayed
Chalk-side via `declare_*`/`seal`. This doc scopes 4c against the *verified*
producer constraints (probed 2026-06-21).

## What 4c is

B::SoN emits a declarative `classes` JSON section; Chalk's loader replays it
through `Chalk::MOP` `declare_class`/`declare_field`/`declare_method`/
`declare_adjust` then `seal()`, sets `Call.class_name`, and the backend lowers
the sealed MOP. The class corpus cases (classes.md) pass the triple check.

## The producer constraint — and why a spike DISSOLVED it (VERIFIED 2026-06-21)

**First read (the apparent blocker):** the Perl 5.42 `class` `new` is a built-in
XSUB — `\&Class::new` has `ROOT = NULL`, `PADLIST = NULL`. So field defaults,
ADJUST, and the param→field binding are NOT in the `new` optree.

**Spike result (the blocker is a red herring):** the field-init and ADJUST
logic do NOT live in `new`. They live in **separate, walkable CVs** on the class
HvAUX struct (`hv.h` xpvhv_aux), reachable via a small XS exactly like the
existing `SoN::FieldInfo`:
- `xhv_class_initfields_cv` — a CV whose optree assigns the field defaults.
  Spike walked it: `methstart, padhv, const(42), helemexistsor, initfield,
  initfield, leavesub` — the default value `42` and per-field `initfield` ops
  are right there.
- `xhv_class_adjust_blocks` — an AV of CVs, one per ADJUST block, each with a
  real optree. Spike walked `ADJUST { $d = $n*2 }` → `padsv, const, multiply,
  leavesub`.
- `xhv_class_superclass` — the `:isa` parent STASH (spike: Child→Counter).
- `xhv_class_param_map` — param-name → fieldix.

So **everything is reachable**. The producer needs a small `SoN::ClassAux` XS
(3-4 accessors into HvAUX) + translating the initfields/ADJUST CVs as graphs.

**Reachable (confirmed):**
- Class name (`B::HV->NAME`), parent (`xhv_class_superclass`).
- Per-field declaration metadata via `SoN::FieldInfo::field_info`: name,
  `fieldix`, fieldstash, param-name (incl. `:param(alias)`), has-`:param`.
  (`:reader` is a synthesized method in the stash — detectable by name.)
- Field DEFAULT values — via the `initfields_cv` optree (NEW, from spike).
- ADJUST bodies — via the `adjust_blocks` CVs (NEW, from spike).
- Method bodies (existing `translate`), method names.

## The consumer already does the hard part (VERIFIED 2026-06-21)

**Chalk's backend SYNTHESIZES the constructor from the declarative MOP** —
B::SoN does NOT produce the constructor body. `_lower_call_new`
(Target/LLVM.pm:4008–4150):
- Binds `:param` values from `Call(new).param_names` (the call-site args).
- For fields not provided as params, applies `has_default` + `default_node`
  (an IR node) from the field declaration.
- ADJUST runs as a separate `@Cls__ADJUST(self)` function called after binding,
  built from the MOP's adjust graph(s).

So the producer needs: declarative field metadata, the **default value as an IR
node** (from `initfields_cv`), method graphs, and the **ADJUST graph** (from
`adjust_blocks`). All four are now reachable (spike). Note an existing CONSUMER
gap: `_lower_call_new` lowers only **Int** field defaults today (Str/ref default
is a tracked Chalk follow-up, LLVM.pm:4106) — independent of 4c.

## Corpus reality (classes.md — 7 cases)

| Case | default value | ADJUST | producible by 4c? |
|---|---|---|---|
| class-simple (`Empty->new; ref`) | — | — | **yes** |
| field-basic (`new(name=>'cat'); name`) | — | — | **yes** |
| field-attrs (`:param :reader` x2) | — | — | **yes** |
| method-simple (`new; greet`) | — | — | **yes** |
| class-isa (`Child :isa(Base)`) | — | — | **yes** (parent via superclass) |
| method-call (`field $n :param = 0; inc; val`) | `=0` (initfields) | — | **yes** |
| adjust (`ADJUST { $double = $val*2 }`) | `=0` | ADJUST cv | **yes** |

**All 7 are producible** — the spike proved defaults + ADJUST are reachable
CVs. (`method-call`/`adjust` use Int defaults, which the backend lowers; a Str
default would hit the pre-existing consumer gap, not a 4c gap.)

## 4c work order (decided: Option A — capture defaults + ADJUST via XS)

1. **4c-0 SoN::ClassAux XS.** ~3–4 accessors into HvAUX: `initfields_cv`,
   `adjust_cvs`, `superclass_name`, (param_map). Spiked + proven. Builds into
   the existing SoN.so next to FieldInfo.xs.
2. **4c-1 declarative class section (producer).** B::SoN detects classes
   (HvAUXf_IS_CLASS), emits `classes{name → {parent, fields[name, fieldix,
   param_name, is_param, is_reader, has_default, default_ref], methods[name→
   graphref], adjusts[graphref]}}`. Field defaults come from translating the
   `initfields_cv` (extract each field's init value as a graph/node); ADJUST
   bodies from translating each `adjust_cvs` entry.
3. **4c-2 Chalk loader replay (consumer).** `from_json` consumes `classes`,
   replays via `declare_class/field/method/adjust` + `seal`, wires the default
   node + ADJUST graph, returns `($graphs, $mop)` (scalar-context compatible).
4. **4c-3 method dispatch + Call.class_name.** `Call(method)` for `$obj->meth`
   and `Class->new` produced with `class_name` set from the class section; the
   corpus class cases lower via `lower(mop => $sealed)` to lli==perl.

Sub-stage gating: 4c-1 needs 4c-0; 4c-2 needs 4c-1's JSON shape; 4c-3 needs the
sealed MOP from 4c-2. The corpus triple-check (behavior/shape/invariant) is the
gate, same as 4b. Cross-repo: 4c-0/4c-1 are perl5-son (producer); 4c-2/4c-3 are
Chalk (consumer); the e2e/son-compare harness is the integration gate.
