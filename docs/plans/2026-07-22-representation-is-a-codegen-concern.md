# Representation is a Codegen concern — and Chalk ALREADY treats it that way

ABOUTME: Finding + its refutation — the IR `representation` field is MISNAMED (it
ABOUTME: carries a semantic type stamp); the type/repr separation already exists.

Date: 2026-07-22
Status: RESOLVED by PAAD pushback (2026-07-22) — verdict (b): NAMING problem, not
an architecture problem. The arc originally proposed here would rediscover the
status quo. Right-sized fix: rename/redocument the field. See "## PUSHBACK
RESOLUTION" at the end.
Origin: perigrin, 2026-07-22 — "Num and Str sharing a PV is a perl representation
choice, not semantic; letting Codegen decide representations per-platform would
yield performance benefits." (The PRINCIPLE is correct; the codebase already
honors it — the finding below mis-located it as a violation to fix.)

## The finding

Chalk's IR nodes carry a `representation` field (Node.pm:41-56) whose VALUES
('Int', 'Num', 'Str', 'Bool', 'Undef') are a MACHINE-representation lattice, and
that field is ASSIGNED in the semantic/loader layer — UPSTREAM of any target
being chosen. This is a layering violation: representation is a per-target
lowering decision, but the shared IR commits to one before Codegen runs.

### Evidence (verified 2026-07-22)

1. **The field is documented as a lowering concern but populated pre-Codegen.**
   Node.pm:50 comment: "representation is a per-use lowering [concern]" and :54
   "Coerce nodes bridge between representations on edges." So the design KNOWS
   repr is a lowering concern — yet `set_representation` setter counts are:
   - IR/semantic layer: 18 (Node.pm:3 + Serialize/JSON.pm loader:15)
   - Codegen/Target layer: 1 (Target/LLVM/Context.pm)
   Representation is decided ~18:1 in the semantic layer, dominated by the JSON
   loader — i.e. at load time, before a target is selected.

2. **PV-sharing is NOT semantic — Chalk's own primary backend already rejects it.**
   The "Num and Str share a PV" fact is perl-runtime-specific. The LLVM backend
   gives them DISTINCT representations (Context.pm:17-21): Int->i64, Str->%StrPair,
   Num->double, Bool->i1, Undef->i1. Four distinct reprs, none shared. So
   assuming PV-sharing (or any single representation choice) at the semantic layer
   is wrong for Chalk's actual target — it imports one runtime's storage decision
   into the type/IR layer where it does not belong.

3. **The Coerce node is semantically right but repr-typed.** Coerce carries
   `from_repr`/`to_repr` (Node/Coerce.pm:16-20) and `_lower_coerce` dispatches on
   them (Context.pm:1022-1039: `if from eq 'Int' && to eq 'Num' -> sitofp`). The
   coercion EDGE is correct and explicit (good). But keying it on `*_repr` means
   the coercion's existence and cost are fixed at the semantic layer, not chosen
   by the target.

## Why it matters (the performance thesis)

If representation were a per-target Codegen decision instead of a semantic-layer
commitment, each backend could choose representations optimal for its platform
AND lower-or-ELIDE coercions accordingly:

- A target that represents Int and Num identically (some GPU/FP targets) could
  DELETE a `Coerce(Int->Num)` as a no-op. Today it is baked in.
- A target could keep Str numeric-parse-cached (numify once), making
  `Coerce(Str->Num)` a cache read.
- A target could unbox Int to a register, tag a DualVar as an actual pair, etc.
- The `"42"`/`"hello"` "static-membership unsoundness" objection DISSOLVES: the
  semantic layer never asserts a value's representation, so there is nothing to
  be unsound about. It narrows TYPES and emits semantic Coerce EDGES; the target
  decides whether any given coercion costs anything.

The current design forecloses all of this by committing representation in the
loader.

## The clean architecture this implies

- **Semantic / IR layer:** nodes carry a semantic TYPE (Int, Num, Str, ... with
  membership + `<:`), and Coerce edges are semantic `Type -> Type`. NO
  `representation` field on the shared IR. The graph is representation-free.
- **Codegen (per target):** a repr-ASSIGNMENT pass maps semantic types -> this
  target's representations (LLVM: i64/double/%StrPair; Perl: SV; future: unboxed/
  tagged), then lowers or elides each Coerce per its own repr choices.
  `_lower_coerce`'s `from_repr/to_repr` dispatch is the right SHAPE — it just
  belongs AFTER a target-owned repr-assignment, consuming target reprs rather
  than a repr baked in at load.

## Honest scope caveats (not yet resolved — for the pushback to test)

- The `representation` field may be doing DOUBLE DUTY: partly a genuine semantic
  type-stamp from B::SoN's analysis, partly a lowering hint. Separating "semantic
  type" from "target representation" cleanly is the actual work, and it is
  non-trivial — it touches the 18 setters, the Coerce node's from_repr/to_repr
  naming/contract, `_lower_coerce`, and the wire format.
- B::SoN's stamps (Int/Num/Str/Scalar) ARE semantic types (the repr lattice
  doubles as the type lattice today). Untangling type-vs-repr may reveal they are
  genuinely the same 4 points and the "leak" is nominal, OR that repr needs to be
  a distinct richer per-target thing. UNKNOWN — test it.
- Byte-compat: B::SoN self-hosting depends on Chalk Graph::nodes() walk order.
  A repr-assignment refactor must not perturb node identity/order.
- This aligns with the standing STRUCTS-DELETE decision (memory: the metadata
  structs delete eventually; the LLVM backend reads the MOP directly) — repr
  becoming a Codegen pass is the same direction.

## What this is NOT claiming

- Not that the Coerce-node design is wrong (it is right — explicit coercion edges).
- Not that TypeInference's `<:` lattice is wrong (it is the semantic type layer).
- Not a quick fix — this is arc-sized (separate semantic type from target repr).

## Evidence base

- IR carries a repr field, documented as lowering-concern: Node.pm:41-56.
- LLVM gives Int/Num/Str/Bool distinct reprs (PV-sharing not semantic):
  Context.pm:15-23.
- Coerce keyed on from_repr/to_repr: Node/Coerce.pm:16-20; _lower_coerce
  Context.pm:1019-1046.
- Aligns with structs-delete / LLVM-reads-MOP decision: memory.

## PUSHBACK RESOLUTION (PAAD adversarial review, 2026-07-22)

**VERDICT (b): naming/framing problem — the clean architecture MOSTLY ALREADY
EXISTS. The arc above would rediscover the status quo.** What the review found:

1. **The "leak" is NOMINAL.** The field carries SEMANTIC TYPES, not machine
   reprs. `%STAMP_TO_REPR` (JSON.pm:24-31) is a near-identity rename of B::SoN's
   TYPE lattice (comment JSON.pm:19-21: "Stamp lattice: Int < Num < Str <
   Scalar"). The 15 loader sites DESERIALIZE + INFER what the value IS
   (`_propagate_computed_reprs` JSON.pm:1043-1107 is type inference: Subscript =
   element type, Assign = rhs type, widest-join over the type chain).
   TypedInvariant.pm:18-26 encodes Perl operand SEMANTICS ("Perl / is always float
   division"), not layout. Machine layout is chosen ONLY in the backend
   (Context.pm:15-23: 'Int'->i64, 'Str'->%StrPair). **Types-in-IR /
   repr-mapping-in-Codegen is the IMPLEMENTED architecture** — with a misleading
   field name.

2. **The performance thesis FAILS — the backend already has the freedom.**
   `_lower_coerce` already ELIDES identity coercions (Bool->Bool pass-through,
   Context.pm:1042-1046); a target repping Int and Num both as double elides
   Coerce(Int->Num) the same way, changing only its emitters. The backend already
   INSERTS coercions with no Coerce node (numify inline at numeric compare,
   Context.pm:1643). Nothing upstream forecloses per-target repr. numify-caching /
   unboxing need NO IR change — backend-local work.

3. **My evidence was miscounted.** The "18:1 ratio" was wrong (Node.pm "3" was
   comments + the method def, zero assignments). Wire format is ALREADY
   repr-free: `to_json` emits no `representation` key (only the producer stamp);
   the loader recomputes. Field excluded from content_hash (Node.pm:50). So
   "commits repr before Codegen" and "touches the wire format" are both false.

4. **The Coerce subsystem is DORMANT** — zero production creation sites in either
   repo. Renaming its from_repr/to_repr is churn (they're in content_hash + wire
   keys) for near-zero gain.

**What SURVIVES (correctly sized):**
- The naming genuinely MISLEADS — badly enough it misled this finding's author
  into an arc-sized claim. Node.pm:41/:50 says "machine-level representation... 
  per-use lowering decision" while the field IS a semantic type stamp. Fix:
  rename/redocument the field as a semantic TYPE stamp; fix Node.pm's
  "machine-level" language. Keep wire keys + content_hash strings byte-identical
  (zero corpus/byte-compat risk).
- `'Slot'` (JSON.pm:1061) named for machine layout when the semantic type is
  "possibly-undef" — a real naming smell.
- **The DEFERRED structural point (perigrin's real insight, correctly filed):**
  if a SECOND backend ever needs different lattice GRANULARITY (IV/UV/NV split, or
  genuinely per-platform reprs), the single semantic-tag-doubles-as-repr WILL
  pinch and need the type/repr separation described above. There is exactly one
  target today (Target/ is LLVM-only), so this is a decision to make WHEN a second
  target exists — not an arc to run now.

**Right-sized actions:** (1) rename/redocument the field (naming, zero-risk);
(2) file numify-caching/unboxing as backend-local perf work; (3) record the
deferred type/repr separation for when a second backend arrives. NOT an arc.
