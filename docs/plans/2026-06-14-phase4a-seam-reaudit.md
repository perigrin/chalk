# Phase 4a — Seam Re-Audit: B::SoN vs Today's Chalk IR/MOP

**Date:** 2026-06-14
**Stage:** Phase 4, Stage 4a (read-only audit; no production code changed)
**Brief:** `docs/plans/2026-06-12-phase4-bson-brief.md`
**Repos audited:**
- Chalk: `/home/perigrin/dev/chalk/.claude/worktrees/pu` @ `phase1-lateral-bindings` (HEAD fbe812c0)
- perl5-son: `/home/perigrin/dev/perl5-son` (FromOptree last touched Apr 11)

**Method note:** Findings marked **[confirmed]** were verified by reading the
cited source or running the cited command. Findings marked **[inferred]** are
deductions from code structure not directly executed. All timestamps via `date`
(2026-06-14 04:01 UTC at audit start).

---

## Headline numbers (correcting the stale April figures)

| Figure | April (stale) | Today (re-derived) |
|---|---|---|
| Chalk live data/CFG node classes | 76 | **84** (`ls lib/Chalk/IR/Node/*.pm`) [confirmed] |
| Chalk `%DATA_CLASSES` ops | — | 78 ops (NodeFactory.pm:88–105) [confirmed] |
| perl5-son node classes (own tree) | 70 | **77** (`ls lib/SoN/IR/Node/*.pm`) [confirmed] |
| **Node-parity headline** | "70 of 76" | **77 of 84** Chalk node classes have a same-named B::SoN class; but only **~40 are actually *emitted* by FromOptree** (see §1) [confirmed] |
| Cross-load tests | "25" | cross-load-son-json.t = **31 pass**; ir-serialize-json.t = **37 pass** [confirmed run] |
| "Zero unsupported ops" | claimed | Still true *for the subset B::SoN emits* — Test 8 whitelist is hardcoded and stale (omits ExpressionList/Coerce/RegexCapture/EnvRead) but B::SoN emits none of those, so it passes vacuously [confirmed] |

**The "77 of 84" class-parity number is misleading and should be retired the
same way "70 of 76" was.** Class-file *existence* in perl5-son's mirror tree is
not the contract. The real contract is what `SoN::FromOptree` *emits*, which is a
much smaller set, and which is missing exactly the tiers Phase 4 must close
(MOP/class, regex-capture, host, Coerce).

---

## 1. NODE PARITY (re-derived from what FromOptree actually emits)

Source of truth for the producer side: `SoN::FromOptree::OpMap` (the
opcode→node table) plus the special-case handlers in `SoN::FromOptree::translate`
(OpMap node_type is overridden for several ops). [confirmed by reading both]

### 1a. What B::SoN emits, mapped to today's Chalk vocabulary

**Produces a Chalk match (emitted by FromOptree, lands on a live Chalk node):**
Constant, PadAccess, FieldAccess, StashAccess, Add, Subtract, Multiply, Divide,
Negate, Modulo, Power, BitAnd, BitOr, BitXor, Complement, LeftShift, RightShift,
Concat, Length, Stringify, Repeat, NumEq/Lt/Gt/Le/Ge/Ne/Cmp, StrEq/Lt/Gt/Le/Ge/Ne/Cmp,
Not, Xor, Defined, Assign, DefinedOr (special-cased, FromOptree.pm:50),
TernaryExpr (cond_expr special-case, :71), Call (entersub + every builtin),
Subscript (aelem/helem), Slice, ArrayRef (anonlist), HashRef (anonhash),
Ref (refgen/srefgen), IsaOp, VarDecl (padsv_store+OPpLVAL_INTRO, :401),
RegexMatch (match special-case, :431), RegexSubst (subst special-case, :457),
AnonSub (anoncode), BacktickExpr, Start/Return/Unwind (die→Unwind, :469),
If/Proj/Region (and/or/loop branch handling), Loop, Phi (loop-var merge, :197).
[confirmed]

**Produces a NOW-DELETED node:** **NONE.** The 18 R3-deleted node names
(ClassDecl, MethodDef, FieldDef, FieldWrite, MethodCall, New, AdjustBlock,
ArrayRead, ArrayWrite, HashRead, HashWrite, ArrayLiteral, HashLiteral,
MakeArrayRef, MakeHashRef, ScalarLen, ArrayDeref, HashDeref) appear nowhere in
OpMap or FromOptree. [confirmed: `grep` for each name = 0 producer files]
B::SoN never modeled the class/MOP tier, so it never depended on the deleted G5
vocabulary — it is *behind* it, not *coupled to* it. Array/hash ops were always
funneled to Subscript/Slice/Call, not the deleted ArrayRead/HashWrite family.

**Produces NOTHING for a live Chalk node (the gap set):**
- **RegexCapture** — Chalk's `$1..$9` contract (RegexCapture.pm: inputs[0] = the
  RegexMatch node, value = capture slot N). B::SoN has **no RegexCapture class
  and no producer**. `$1` in an optree is a `gv`/`gvsv` → emitted as a
  Constant(name) or StashAccess, NOT wired to the match. [confirmed: 0 producers;
  probe of `$s =~ /.../ ; $1` shows no capture node]
- **EnvRead** — Chalk's `$ENV{KEY}` host node. B::SoN: `$ENV{...}` lowers as
  helem→Subscript on a StashAccess. No EnvRead. [confirmed: 0 producers]
- **Coerce** — the typed-IR edge-materialized coercion node. B::SoN emits no
  stamps-on-edges discipline and no Coerce. [confirmed: 0 producers]
- **ExpressionList** — Chalk uses it for multi-value positions. B::SoN models
  these as `aassign`/mark-pops; no ExpressionList node. [confirmed: 0 producers]
- **ListAssign** — Chalk has a dedicated per-position ListAssign node
  (NodeFactory.pm:272); B::SoN folds `aassign` → generic `Assign`. [confirmed]
- **CompoundAssign** — present as a Chalk node and a B::SoN class, but
  FromOptree maps `+=`/`-=` etc. (preinc/predec/postinc/postdec and andassign/
  orassign/dorassign) to **Call** or branch handling, never CompoundAssign.
  [confirmed: OpMap:70–77,153–155 → 'Call'/BRANCH]
- **Match / NotMatch** — Chalk's bind operators. B::SoN routes `match`/`subst`
  to RegexMatch/RegexSubst, and `smartmatch` to Match; the `=~`/`!~` *binding*
  distinction is lost. [confirmed: OpMap:247–248 overridden by special-case]
- **StructRef / StructFieldAccess** — registered as B::SoN classes but no
  FromOptree producer. [confirmed]
- **Interpolate** — registered, no producer (FromOptree has no string-interp
  reconstruction; `multiconcat`→Concat). [confirmed]
- **Aggregate / Access / Regex / Region(as data)** — Chalk-only or unemitted.

**Net producer parity:** Of 84 Chalk node classes, B::SoN's FromOptree *emits*
roughly **40**. The class-name mirror tree (77) overstates coverage by ~2x
because dozens of registered SoN node classes have no FromOptree producer.

### 1b. The MOP tier is entirely absent on the producer side

B::SoN emits **per-method/per-sub graphs keyed by fully-qualified name** (`B::SoN.pm`
`_discover_and_translate` walks stashes, translates each CV). There is **no
`Chalk::MOP` emission, no `declare_class`/`declare_field`/`declare_method`/`seal`,
no MOP::Class/Field/Method nodes, no Call.class_name**. [confirmed: 0 producers
for declare_class/seal/MOP; probe of class file below]

Probe (`Counter` class, `field $n :param = 0; method inc { $n += 1 }`):
```
=== Counter::inc ===
%1 = FieldAccess(index: 0, stash: 'Counter')
%2 = Constant(1) [Int]
%3 = Add(%1, %2)
%4 = Return(%0, %3)
```
[confirmed run] Two independent failures visible here:
1. **No class structure** — only the two method bodies surface, named
   `Counter::inc`/`Counter::val`. The `class Counter`, the `field $n :param = 0`
   declaration, and the implicit constructor produce **no MOP output at all**.
2. **Field write dropped** — `$n += 1` lowers to `FieldAccess; Add; Return`. The
   store back into field slot 0 is **absent**. There is no Assign/FieldWrite
   wiring the `Add` result back to the field. The debt "drops field writes" is
   **STILL TRUE**.

---

## 2. KNOWN DEBTS RE-MEASURED

### Debt A — FromOptree PadAccess `targ` bug
**Status: STILL PRESENT (cosmetic-but-real).** `targ` is serialized verbatim
(FromOptree.pm:380, :656, :787 all `PadAccess(targ => $targ, ...)`; Serialize emits
it, Serialize/JSON.pm:59). The pad index is **CV-local and unstable** across
compilation units, so it cannot be a cross-graph identity key. Chalk's
`_deserialize_graph` takes `targ`/`varname` straight through (Serialize/JSON.pm:265–267),
so a stale `targ` loads as-is. This is the noted "method-level comparison blocker":
two graphs that are semantically identical diverge on `targ`. The brief schedules
the fix in 4b. [confirmed by reading; not independently reproduced as a
comparison failure because son-compare's trivial methods have no pads]

### Debt B — "Fails on `feature class` method bodies / zero overlap for class files"
**Status: PARTIALLY OBSOLETE / RE-CHARACTERIZED.** Method *bodies* now DO
translate — `Counter::inc`/`val` produced clean graphs (probe above), and the XS
`FieldInfo` component (`blib/arch/auto/SoN/SoN.so`, built; `is_field`/`field_info`
via `FieldInfo.xs`) correctly distinguishes `FieldAccess` from `PadAccess`
(FromOptree.pm:880 `_make_pad_or_field`). So **single-exit method bodies are no
longer zero-overlap.** What remains true:
- **Field writes dropped** (Debt re-confirmed, §1b).
- **No class structure / MOP** (§1b) — so a class *file* still yields only loose
  method graphs with no class binding; from the corpus's perspective
  (classes.md needs MOP::Class/Field/Method) this is still "can't produce."
[confirmed]

### Debt C — "No MOP emission"
**Status: STILL FULLY TRUE.** §1b. This is the single largest producer-side gap
and the gate for 4c. [confirmed]

### Debt D — son-compare current divergences (re-measured)
The harness (son-compare.t) compares **Chalk-parser IR** (via
`script/chalk-emit-son-json`, which uses the *Chalk Earley parser*, NOT B::SoN —
line 8–10) against **B::SoN IR**, per method, as an unordered+ordered op
multiset. [confirmed by reading]

I characterized the divergence directly (the full 84-case run is slow — full
grammar rebuild per file — so I sampled `Add.pm` under the exact harness command
`perl -Ilib -I$son_lib -MO=SoN,json,package=...`):

```
BSON  Chalk::IR::Node::Add::operation: Start,Constant,Return
Chalk Chalk::IR::Node::Add::operation: Constant,Return,Start
```
[confirmed run] **The divergence is pure node ORDERING, not a semantic gap.**
Same multiset {Start, Constant, Return}, same count (3=3), different serialization
order: B::SoN's `_serialize_graph` walks `graph->nodes` (DFS from Start →
Start-first), Chalk's emits Start last. The test's exact-sequence check
(`join(',')`, son-compare.t:64) flags this as `diverged`; the multiset check
(only_bson/only_chalk) is **empty**. Every trivial Node-file method
(`op_str`/`operation` returning a constant) diverges this way — `B::SoN=N Chalk=N`
with empty exclusive-op sets. **None of these divergences is attributable to the
targ bug, missing MOP, deleted-node vocabulary, or a genuine semantic gap.** They
are a serializer node-ordering convention mismatch.

**Caveat:** the corpus the harness uses is `lib/Chalk/IR/Node/*.pm` — trivial
accessor methods. It does **not** exercise field writes, multi-exit bodies,
regex, or aggregates, so son-compare's *current* green-modulo-ordering state
does NOT certify the hard tiers. The mdtest corpus (§4) is the real work-list.

---

## 3. CROSS-LOAD OF THE NEW VOCABULARY

Two round-trip directions, both run [confirmed]:

### 3a. Chalk → JSON → Chalk (`ir-serialize-json.t`, 37/37 pass)
The new G6/G7 vocabulary survives Chalk's own round-trip:
- **RegexCapture** `n` preserved (test 32–33).
- **EnvRead** `key` preserved (test 34–35).
- **Call.class_name** + `param_names` preserved (Serialize/JSON.pm:46–51 emit;
  :251–257 reload; test 36–37). [confirmed]
- Per-call identity: `from_json` rebuilds every node through Chalk's
  **NodeFactory** (`_deserialize_graph`, Serialize/JSON.pm:229,304–307), so
  STATEMENT_EFFECT_OPS / ALLOC_OPS get fresh `#N` ids on load. Identity is
  **reconstructed by the loader**, not carried in the JSON (the JSON uses
  positional ids 0..n). [confirmed by reading]

### 3b. B::SoN → JSON → Chalk (`cross-load-son-json.t`, 31/31 pass)
Loads B::SoN JSON into Chalk IR for the subset B::SoN emits (Constant, Add,
TernaryExpr, Unwind, Ref, Length, Slice). Test 8 asserts "all B::SoN node types
supported by Chalk NodeFactory" — passes, but only because B::SoN emits none of
the four nodes the whitelist omits. [confirmed]

### 3c. Where the two serializers AGREE vs DIVERGE
Both `Chalk::IR::Serialize::JSON` and `SoN::Serialize::JSON` share the schema:
`{version, source, methods{name → {nodes[], start, returns[]}}}`, positional
ids, `cfg` flag, `fields` sub-hash. **Agree** on: Constant, Call(dispatch_kind+name),
Phi(region), Proj(index), PadAccess(targ,varname), FieldAccess(field_index,
field_stash), StashAccess, CompoundAssign(op), PostfixDeref(sigil),
RegexMatch(pattern,flags), RegexSubst(pattern,replacement,flags), VarDecl(scope).
[confirmed by diffing the two `_extract_fields`]

**Diverge:**
- **B::SoN emits `stamp`** on every node (SoN/Serialize/JSON.pm:123–125); Chalk's
  serializer emits no `stamp` and Chalk's loader **ignores** it. The typed-IR
  representation does not survive B::SoN→Chalk load — it is dropped. [confirmed]
- **Chalk emits, B::SoN cannot:** `class_name`/`param_names` on Call,
  `n` on RegexCapture, `key` on EnvRead (Chalk Serialize/JSON.pm:46–95). B::SoN's
  `_extract_fields` has no arms for these (it has no such nodes). One-directional. [confirmed]
- **Node ordering** (§2 Debt D): different traversal order → exact-sequence
  mismatch even when the node sets are identical.

**Bottom line:** the JSON schema is compatible for the emitted subset and Chalk's
loader is the more capable of the two. The gaps are *missing producers*, not
*incompatible formats*.

---

## 4. THE GAP MAP (seeded from mdtest corpus perl sources)

12 corpus files. Classification by what `SoN::FromOptree` visibly handles
(I did not run B::SoN on every case; producible = a known producer path exists,
blocked = hits a named debt, needs-MOP = requires the class tier). [inferred from
FromOptree reading + targeted probes where noted]

### Computation slice

| Topic / case | Verdict | Evidence |
|---|---|---|
| arithmetic (all 5) | **producible-now** | add/subtract/multiply/divide/modulo all in OpMap → live nodes |
| variables A1 (my+read) | **producible-now** | padsv_store+OPpLVAL_INTRO→VarDecl (:401) |
| variables A4 (my then assign) | **producible-now** | sassign→Assign (:388) |
| variables **A5 (field param read)** | **needs-MOP-contract** | FieldAccess emits, but the class+:param structure needs the MOP (classes.md tier) |
| variables C1 (reassign+read) | **producible-now** | sassign rebinds scope (:392) |
| variables C2 (compound assign) | **blocked-by-CompoundAssign-gap** | `+=` → Call/branch, not CompoundAssign |
| increment K1/K2 (++/--) | **blocked-by-increment-modeling** | preinc/postinc → **Call** (OpMap:70–77); semantics + return-value-of-postinc unverified |
| logical L1/L2 (and/or) | **producible-now** | and/or branch handling builds If/Proj/Region (:105) |
| logical L3/L3b (//) | **producible-now** | dor special-case→DefinedOr (:50) |
| logical L4 (not) | **producible-now** | not→Not |
| strings S1/S2 (literals) | **producible-now** | const→Constant |
| strings S3 (concat) | **producible-now** | concat/multiconcat→Concat |
| strings S4 (.=) | **blocked-by-CompoundAssign-gap** | concat-assign is a compound op |
| strings S5 (non-ASCII) | **GAP (corpus-declared)** | encoding GAP independent of B::SoN |
| control-flow D6 (ternary) | **producible-now** | cond_expr→TernaryExpr (:71) |
| control-flow D1 (if/else) | **producible-now** | and/or/cond branch → If/Proj/Region |
| control-flow D2/D3/D5 (while/foreach/postfix-while) | **producible-now (suspect)** | enterloop/enteriter→Loop+Phi (:178); loop-Phi correctness unverified, flagged by Gate 0 `_wire_region_phis` |
| control-flow D4 (postfix if) | **producible-now** | lowers to and/or |
| control-flow D7/D9 (nested if) | **producible-now (suspect)** | nested branch merge via `_walk_branch` convergence |
| control-flow **D8 (try/catch)** | **blocked-by-trycatch-modeling** | entertrycatch special-case (:144) builds a Region merge but **emits no TryCatch node**; Chalk has a TryCatch statement-effect node it doesn't produce |
| references R1 (array+count) | **producible-now** | anonlist→ArrayRef, av2arylen→Length |
| references R2/R8 (elem read/nested) | **producible-now** | aelem→Subscript |
| references R3/R10 (hash read/missing) | **producible-now** | helem→Subscript |
| references R4/R5 (anon ref+deref) | **producible-now** | refgen→Ref, rv2*→deref |
| references **R6/R7 (elem/key assignment)** | **blocked-by-field/elem-write-drop** | same store-drop class as field writes; aelemfastlex_store→Assign exists (OpMap:195) but element-store wiring unverified and the §1b drop is the live risk |
| references R9 (OOB read) | **producible-now** | Subscript |
| references R11 (sorted keys) | **producible-now** | sort/keys→Call |
| statements (return int / multi-stmt / cmp-cond / bare bool) | **producible-now** | const/return/cmp all covered |
| statements (use strict / use List::Util) | **GAP (corpus-declared compile-time)** | pragmas have no runtime optree |
| subs F1 (named) | **producible-now** | _walk_package emits named CVs |
| subs F2 (anon) | **producible-now** | anoncode→AnonSub |
| subs F3 (chained calls) | **producible-now** | entersub→Call |

### Class / regex / host tier

| Topic / case | Verdict | Evidence |
|---|---|---|
| classes class-simple (`class Empty{}` + ->new) | **needs-MOP-contract** | no MOP emission; `Empty->new` needs Call.class_name |
| classes field-basic / field-attrs | **needs-MOP-contract + blocked-by-field-write** | FieldAccess emits; MOP::Class/Field/Method absent |
| classes method-simple | **needs-MOP-contract** | method body emits, class binding absent |
| classes method-call (`$n += 1`) | **needs-MOP-contract + blocked-by-field-write-drop** | §1b probe: store dropped |
| regex (match-as-cond, capture) | **blocked-by-RegexCapture-gap + Gate-0** | RegexMatch emits; `$1` NOT wired to match (no RegexCapture); Gate 0 item 1 (RegexMatch identity) must land first (brief 4d) |
| regex s/// | **producible-now (suspect)** | subst→RegexSubst (:457); replacement extraction is fragile (only handles Constant repl) |
| host (`$ENV{...}`, `$1`) | **blocked-by-EnvRead-gap + RegexCapture-gap** | no EnvRead, no capture wiring |

**Multi-exit bodies (cross-cutting):** any corpus method with an early
`return X if COND` is **blocked-by-multi-exit** on BOTH sides — see §5(c). Probe:
`sub er { ...; return 1 if $x; return 2 }` produced **no output** (silently
swallowed by B::SoN.pm:102 `catch{}`). [confirmed run]

---

## 5. THE THREE OPEN DECISIONS — grounded recommendations

### (a) Conversion locus: Chalk-shaped JSON, or in-process NodeFactory?
**Recommendation: keep the JSON seam (B::SoN emits Chalk-shaped JSON,
`Chalk::IR::Serialize::JSON::from_json` loads it) — do NOT have B::SoN construct
Chalk nodes in-process.**

Evidence: The per-call identity contract is *already* satisfied by the JSON path,
**because Chalk's loader reconstructs identity through Chalk's own NodeFactory**
(`_deserialize_graph` calls `$factory->make/make_cfg`, Serialize/JSON.pm:229,304;
NodeFactory.pm:153–297 assigns `#N` ids to STATEMENT_EFFECT_OPS/ALLOC_OPS on
construction). The JSON carries only positional ids 0..n; identity is *minted by
the consumer*. This routes through exactly ONE factory (Chalk's) regardless of
what B::SoN's own NodeFactory does — and B::SoN's factory hash-conses ALL data
nodes with no `#N` counter (SoN NodeFactory.pm:25–40), which is the *wrong*
identity semantics. Constructing Chalk nodes in-process from perl5-son would
require loading Chalk's entire IR/factory/MOP tree into the B::SoN process (heavy
coupling) AND re-implementing or importing the identity rules. The JSON seam
already isolates that. [confirmed by reading both factories + both loaders]
**One caveat for 4b:** B::SoN must serialize per-call effects as *distinct JSON
nodes* (it currently can, since positional ids are per-node) — the hash-consing
risk lives only if B::SoN's *own* factory collapses two identical effects
*before* serialization. Verify B::SoN emits two Assign entries for two identical
`$x = 1` statements; if it collapses them (its factory will), that is a 4b bug to
fix on the producer side.

### (b) MOP emission side: build Chalk::MOP in perl5-son, or emit declarative JSON replayed Chalk-side?
**Recommendation: emit a declarative class-structure JSON section; replay it
Chalk-side through `declare_*`/`seal`.**

Evidence: `Chalk::MOP` is **not cheaply loadable from perl5-son** — `Chalk::MOP`
`use`s `Chalk::IR::Graph`, `Chalk::IR::NodeFactory`, `Chalk::MOP::Class/Field/
Method/Sub/Import/Phaser`, and `Chalk::Bootstrap::Bindings` (MOP.pm:7–12)
[confirmed]. Building the MOP in-process drags Chalk's whole IR tree into the
B::SoN runtime, the same coupling rejected in (a). The corpus *already*
establishes the replay precedent: classes.md ir-blocks use a declarative
`MOP::Class / MOP::Field / MOP::Method` vocabulary (classes.md field-basic block)
[confirmed], and the MOP gained `seal()` as the post-parse immutability boundary
(`docs/plans/2026-06-11-llvm-reads-mop-directly.md` §2). So: B::SoN emits a
`classes` JSON section (name, parent, fields[name,fieldix,param,reader,default,
type], methods[name → graph-ref], adjusts[graph-ref]); Chalk's loader replays it
via `declare_class/declare_field/declare_method/declare_adjust` then `seal`, and
sets `Call.class_name` from the class section. This keeps perl5-son free of
Chalk internals and puts identity/sealing on the one trusted (Chalk) side. The
producer work is extracting class structure from the optree's pad fieldinfo
(the XS `FieldInfo` already exposes `field_info`) + stash walking — this is the
bulk of 4c.

### (c) Multi-exit method bodies: gap-map entry, or early single-exit normalization in FromOptree?
**Recommendation: normalize to single-exit (merge returns through a Phi/Region)
in FromOptree — do not park it as a pure gap-map entry.**

Evidence: this is a **double blocker**, worse than the brief assumes:
1. **Consumer side:** `Chalk::Target::LLVM::_method_body_root` *dies* on >1
   Return ("multi-exit method bodies are not lowered yet", LLVM.pm:360–363)
   [confirmed]. The L corner cannot lower a multi-return body at all.
2. **Producer side (new finding):** FromOptree does **not even produce** a
   multi-exit body — its `return` handler returns the graph immediately at the
   FIRST `return` op (FromOptree.pm:290–304), and real early-return subs are
   silently swallowed by B::SoN.pm:102 (`sub er { return 1 if $x; return 2 }` →
   no output) [confirmed run]. Even where a body limps through, you get a
   truncated graph with orphan post-Return nodes (observed in
   `JSON::PP::_encode_surrogates`: a `Return(%0,%7)` mid-stream followed by
   live %9–%11) [confirmed run].

Real `lib/` methods are early-return-heavy, so leaving this as a gap-map entry
strands a large fraction of the capstone corpus. The right fix is producer-side
single-exit normalization (collect all returns, merge via Region+Phi into one
Return) — which *also* satisfies the LLVM single-Return root for free. The P
corner (schedule-driven) could in principle take multi-Return, but since the
producer doesn't emit it correctly anyway, normalizing at the FromOptree seam is
the lower-risk single fix that unblocks both corners. Schedule this early in 4b,
not deferred to a gap list.

---

## Single biggest blocker for 4b

**Multi-exit (early-return) method/sub bodies — broken on BOTH the producer and
consumer sides.** FromOptree truncates at the first `return` (or the whole sub is
silently dropped by the `catch{}`), and LLVM's `_method_body_root` dies on >1
Return. Almost every real `lib/` method uses early returns, so without single-exit
normalization the computation slice (4b) and class tier (4c) both stall on the
first non-trivial body. This must be fixed before son-compare on real lib/ can be
anything but green-on-trivia.

## Summary of corrected/disproven claims

- "70 of 76 node parity" → **retired**; real producer coverage is ~40 of 84
  emitted; class-name mirror parity (77/84) is not the contract.
- "Zero unsupported ops" → true only vacuously (Test 8 whitelist stale, B::SoN
  emits nothing it omits).
- "Fails on feature class method bodies" → **obsolete**; single-exit method
  bodies translate (FieldInfo XS works). Field *writes* still drop; class
  *structure*/MOP still absent.
- "Drops field writes" → **confirmed still true** (probe §1b).
- "No MOP emission" → **confirmed still true**; largest 4c gap.
- son-compare divergences → **pure node-ordering**, not semantic gaps, on the
  current (trivial-accessor) corpus.
