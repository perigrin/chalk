# Plan/research document staleness audit

**Date:** 2026-08-24
**Status:** AUDIT. Read-only. No document was annotated, corrected, or deleted —
that decision belongs to perigrin. No `lib/` or `t/` file was read for anything
but verification, and none was modified (`git diff --stat lib/ t/` empty).
**Scope:** `docs/plans/` (209 files incl. 5 `.txt`) and `docs/research/` (20 files).
**Oracle:** current code on `phase5-capstone` @ `a96fa571`, plus the producer
`~/dev/perl5-son` @ `10f9e2e`. Where a 2026-08-24 document has already
adjudicated a claim, that adjudication is cited rather than re-measured (per the
brief).
**Exclusion:** the corpus gate was NOT run (another agent holds it). Every
corpus-floor number below is therefore UNVERIFIABLE by measurement and is
reported as such.

---

## Counts

| | |
|---|---|
| Documents in scope | **229** (209 plans + 20 research) |
| Documents examined for status/date | **229** (all) |
| Documents whose load-bearing claims were verified against code | **21** |
| Documents carrying ≥1 STALE or FALSE claim | **9** |
| Individual claims verified | 61 |
| CONFIRMED | 34 |
| STALE | 19 |
| FALSE | 2 |
| UNVERIFIABLE | 6 |

The prioritization that produced 21-of-229 is stated in §"Method and what was
not checked" — it is a targeted sample, not a sweep, and the residual risk is
named there.

---

## RANKED — most likely to mislead a reader, worst first

Ranking is by *damage on landing*: how confidently the document states the wrong
thing, how load-bearing the wrong thing is, and how likely a reader is to arrive
there while doing current work.

### 1. `docs/plans/2026-08-14-representation-is-the-targets-type-system.md` — DESIGN, unannotated, built on a deleted type

**Why worst:** it is a **DESIGN** doc (not a measurement record) in the *exact
area under active work right now* (type vs representation), it is recent enough
to look current, and an entire load-bearing section rests on the `Any` type,
which was **deleted 2026-08-23**. Nothing on the document says so.

The doc's §"`Any` should be UNREACHABLE" is now unreadable-as-written:

> `type_satisfies` (`TypeLibrary.pm:189-202`) has two blanket accepts that are
> functionally identical: `return true if $required_type eq 'Any'` at :190 and
> `return true if $required_type eq 'List'` at :201.

| claim | verdict | evidence |
|---|---|---|
| `return true if $required_type eq 'Any'` at `TypeLibrary.pm:190` | **FALSE (now)** | The `Any` arm does not exist. `grep -c "Any" lib/Chalk/Grammar/Perl/TypeLibrary.pm` → **1**, and that one is the prose comment at :207 (`# Any concrete type satisfies a 'List' position.`). The surviving blanket accept is `return true if $required_type eq 'List';` at :208. |
| "all 43 of its mentions are inside TypeLibrary" | **STALE** | 43 → **1**. |
| `%POLYMORPHIC_TYPES` includes `Any` | **STALE** | `TypeLibrary.pm:188`: `my %POLYMORPHIC_TYPES = map { $_ => true } qw(Scalar List);` — two members, no `Any`. |
| lattice shape `Array -> List -> Any` | **STALE** | `TypeLibrary.pm:39`: `List => 'Unknown'`. `Any` is not the root; `Unknown` is. |
| the `Any`/`List` refusal table row (`Any` / `List` \| 0+ \| die: NOT A VALUE TYPE) | **STALE** | half the row's subject no longer exists. |
| "`_str_len_table` (45 uses in `Context.pm`)" | **STALE** | `grep -c "_str_len_table" lib/Chalk/Target/LLVM/Context.pm` → **27**. |
| `_undef_defined_bit` / `_undef_payload` / `_slot_payload` exist as side tables | CONFIRMED | 7 / 11 / 10 occurrences in `Context.pm`. |
| `%_STR_CONTEXT_OPS` deleted (claimed as landed) | CONFIRMED | `grep -rn "_STR_CONTEXT_OPS" lib/` → 0. |
| step 1 `is_fixed` landed | CONFIRMED | `method is_fixed()` present on `Node/BacktickExpr.pm:14`, `NotMatch.pm:14`, `Unwind.pm:15`, `RegexSubst.pm:16`. |
| `Bool -> Undef` / `Bool -> Str` rows | **STALE (spelling)** | The type is spelled `Boolean` everywhere now (`TypeLibrary.pm:25 Boolean => 'Str'`); `Bool` as a bare type name is gone. The doc uses `Bool` ~10 times. Meaning survives; vocabulary does not. |

**Damage:** the document argues a design conclusion ("`Any` should be
UNREACHABLE", "`Any` and `List` are synonyms as REQUIRED types, and this is
verified in the code, not assumed") whose subject was subsequently deleted. A
reader taking it at face value would go looking for a guard that is gone, and
would reason about a lattice root (`Any`) that is not the root. The phrase
"verified in the code, not assumed" makes it *more* trusted, not less.

### 2. `docs/plans/2026-04-25-audit-3-mop-ir-findings.md` — comprehensively superseded, no marker on the file

**Why second:** it is a 40K findings document full of exact-looking counts and
file:line citations, and essentially every one of them has moved. It IS flagged
as obsolete in `CLAUDE.md` ("the April-2026 '30–40%, 92 dispatch sites, Shim
pending' figures are obsolete") — but that flag lives in `CLAUDE.md`, not on the
document. A reader who greps `docs/plans/` and lands here directly gets no
warning at all.

| claim | verdict | evidence |
|---|---|---|
| "the migration is closer to **30–40% of acceptance criteria**" | **STALE** | `docs/plans/2026-06-10-mop-migration-reaudit.md:25` re-measures "roughly two-thirds complete, vs. April's 30–40%". Adjudicated; cited, not re-measured. |
| `lib/Chalk/IR/Shim.pm:1-227` present, live consumer at `Bootstrap/IR/NodeFactory.pm:8,96` | **STALE** | `ls lib/Chalk/IR/Shim.pm` → No such file. Deleted. |
| "61 sites in `lib/Chalk/Bootstrap/Perl/Actions.pm`" set `compat_class` | **STALE** | `grep -c "compat_class" lib/Chalk/Bootstrap/Perl/Actions.pm` → **0**. |
| "Field declared at `lib/Chalk/IR/Node.pm:23`, read in `class()` at `lib/Chalk/IR/Node.pm:42`" | **STALE (one line right, one line wrong-and-opposite)** | :23 is still `field $compat_class :param :reader = undef;` — correct. But **:42 is not `class()`** — it is the middle of the `representation` field comment (`# Realized lattice ... 'Int' (i64), 'Num' (double/f64)`). `method class()` is at **:174**. A reader following :42 lands on the representation lattice, an unrelated subsystem. |
| `_build_method_graph` (`Actions.pm:1551-1638`) "still active" | **STALE** | `grep -rn "_build_method_graph" lib/` → **0 hits**. Deleted (per `CLAUDE.md`: "`_build_method_graph` deleted"). |
| "Dead/unused IR node types: 4 (`Slice`, `Length`, `Stringify`, `Yada`) ... have a class file in `lib/Chalk/IR/Node/` but no consumer site in `lib/` or `t/`" | **STALE, and one part FALSE** | See finding 3 below — this is severe enough to rank separately. |
| `docs/architecture/mop.md` "does not exist" (:75, :359) | **STALE** | The file exists; created by `a360849e`. |
| `Target/C.pm:1479 generate_c_files($ir,$sa,$ctx)` | **STALE (line + name)** | Now `_generate_c_files($ir, $sa, $ctx)` (underscore-prefixed) at `lib/Chalk/Bootstrap/Perl/Target/C.pm:1764`. The *contract* survives — which is the 06-10 reaudit's point — but neither the name nor the line matches. |

### 3. The "4 dead IR node types" claim — `Stringify` is not merely alive, it is the subject of HEAD

Carried by `docs/plans/2026-04-25-audit-3-mop-ir-findings.md:14`. Ranked
separately because it is the single most *actively* wrong sentence found.

| node | doc says | reality |
|---|---|---|
| `Stringify` | dead; "has a class file in `lib/Chalk/IR/Node/`" | **FALSE both ways.** `lib/Chalk/IR/Node/Stringify.pm` **does not exist** — so the "has a class file" half was either never true or the file was removed. And Stringify is live and load-bearing: the HEAD commit `53d2011e` is titled *"feat: Print takes Str; a non-Str argument is coerced by an explicit Stringify"*, and `_lower_stringify` emits real LLVM (`Target/LLVM/Context.pm:1458-1482`, `Stringify[Int]` digit buffer). |
| `Slice` | dead, no consumer in `lib/` or `t/` | **STALE (t/ half).** 0 `make('Slice')` sites in `lib/`, but **9** test files mention it. |
| `Length` | dead, no consumer in `lib/` or `t/` | **STALE (t/ half).** 0 `make()` sites in `lib/`, but **22** test files mention it. Memory records `scalar @a`→Length as landed Phase-4 work. |
| `Yada` | dead, no consumer in `lib/` or `t/` | **STALE (t/ half).** 0 `make()` sites in `lib/`, **9** test files. |

**Damage:** a reader doing dead-code cleanup and trusting this line would try to
delete `Stringify`, which is the coercion node HEAD just centralized Print onto.

### 4. `docs/plans/2026-07-22-representation-is-a-codegen-concern.md` — already known, restated here for the ranked list

Both headline verdicts measured false on 2026-08-24. Already adjudicated by
`docs/research/2026-08-24-two-ir-architecture-alignment.md`; cited, not
re-derived. I add only the two confirmations the brief asked for:

| claim | verdict | evidence |
|---|---|---|
| "**The Coerce subsystem is DORMANT** — zero production creation sites in either repo" | **FALSE** | **4** creation sites. chalk: `lib/Chalk/IR/Serialize/JSON.pm:1051`, `:1123` (`$factory->make('Coerce', …)`). producer: `~/dev/perl5-son/lib/SoN/FromOptree.pm:115` (`_coerce_to_str`), `:135` (`_coerce_int_to_num`). |
| "the clean architecture **MOSTLY ALREADY EXISTS**" | **FALSE** | `2026-08-24-two-ir-architecture-alignment.md` VERDICT: "**~35% aligned** … the **pass** does not exist." |
| "`%STAMP_TO_REPR` (JSON.pm:24-31) is a near-identity rename of B::SoN's TYPE lattice" | **STALE** | `%STAMP_TO_REPR` is retired in chalk (`grep -rn "STAMP_TO_REPR" lib/` → 0). Replaced by `%LOWERABLE_STAMP` at `lib/Chalk/IR/Serialize/JSON.pm:30`, which is explicitly **not** a rename map: "This is a WHITELIST, not a translation: the two vocabularies agree name-for-name" (`:25-27`). The vocabularies converging is exactly what `2026-08-22-two-lattices-one-ir.md` landed. |
| "18 setters … Node.pm:3 + Serialize/JSON.pm loader:15", later self-corrected to "the 18:1 ratio was wrong" | CONFIRMED (the correction) | Today: 18 in `Serialize/JSON.pm`, 1 in `Target/LLVM/Context.pm`. The doc's own PUSHBACK section retracts the miscount correctly. |

### 5. `docs/plans/2026-07-19-ir-node-unification.md` — a PLAN whose named blocker was resolved underneath it

**Status line:** "PLAN (2026-07-19, perigrin). No code yet." It self-warns
("every file:line below is from that recon and should be re-verified before
editing") — which mitigates, but the *plan steps themselves* are shaped around a
constraint that no longer holds.

| claim | verdict | evidence |
|---|---|---|
| "MAJOR-1 … the merged Chalk type lacks `set_stamp`"; "(`set_control_in`/`set_representation`/`set_schedule_data` exist; **no `set_stamp`**, no `loop_control`)" | **STALE — this was the plan's named blocker** | `method set_stamp($new_stamp)` exists at `lib/Chalk/IR/Node.pm:212`, and `field $stamp :param :reader` at `:20`. The other three confirmed: `set_schedule_data` :203, `set_control_in` :222, `set_representation` :236. |
| "the 6-entry `%STAMP_TO_REPR` seed stays" | **STALE** | Retired; see finding 4. |
| "82 shared subclasses" | **STALE** | 88 in `lib/Chalk/IR/Node/`, 88 in `~/dev/perl5-son/lib/SoN/IR/Node/`. |
| "B::SoN produces no `representation`" | CONFIRMED | `grep -c "set_representation" ~/dev/perl5-son/lib/SoN/FromOptree.pm` → 0. |
| "`%STATEMENT_EFFECT_OPS`" is Chalk's smart-factory table | CONFIRMED | `Chalk::IR::NodeFactory::STATEMENT_EFFECT_OPS` consumed at `lib/Chalk/Bootstrap/Perl/Actions.pm:1718`. |
| "`$phi->set_stamp($join)` (unguarded, FromOptree.pm:2339)" | **STALE (line)** | Now `~/dev/perl5-son/lib/SoN/FromOptree.pm:3119`. Still unguarded; the *other* producer `set_stamp` at :1256-1257 IS guarded by `->can('set_stamp')`. |

**Damage:** moderate. A reader planning the unification would budget a
transitional seam ("the merged type must EITHER add `set_stamp` + …") that has
already been paid for.

### 6. `docs/research/2026-08-22-lattice-unification-audit.md` — a pre-unification snapshot two days from its own resolution

**Why it ranks here:** the content is honest measurement and the document is
disciplined ("Everything below is either quoted from a file I read, or output of
a command I ran"). But it measures the state that `2026-08-22-two-lattices-one-ir.md`
**RESOLVED on 2026-08-23**, and unlike that document it carries **no forward
pointer**. A reader arriving from a grep for `Any` or `Bool` gets a detailed,
credible, obsolete lattice.

| claim | verdict | evidence |
|---|---|---|
| "CHALK MEMBERS (23): Any Unknown None Scalar Undef **Bool** Regex Str Num Int DualVar …" (:203) | **STALE** | `Any` deleted; `Bool` renamed `Boolean` (`TypeLibrary.pm:25`). Post-unification the two lattices agree 25/25 with 0 divergence — measured in `2026-08-22-two-lattices-one-ir.md` §Outcome. |
| "CHALK-ONLY: Any **Bool** GlobRef Array Hash Code" (:208) | **STALE** | The whole divergence class is closed; `Array`/`Hash`/`Code` were added to the producer side (`f6378e36`). |
| "`:38` `Glob => 'Any'`" (:218) | **STALE** | `Any` is gone from `TypeLibrary.pm` entirely. |
| "**Top:** `Unknown := V` and `Any := V`. Both are top; they are co-located." (:93) | **STALE** | `Unknown` is the sole root (`TypeLibrary.pm:39 List => 'Unknown'`). |
| "`lib/Chalk/IR/Serialize/JSON.pm:518/520/555` `$STAMP_TO_REPR{…}`" (:229-231) | **STALE** | Symbol retired. `from_repr`/`to_repr` are now read at `:509` under a comment saying they "are REPRESENTATIONS named in the producer's stamp" vocabulary. |

### 7. `docs/plans/2026-07-22-coercion-architecture-slice-plan.md` — plans work that has since been done

| claim | verdict | evidence |
|---|---|---|
| ":185 `JSON loader Coerce arm exists; perl5-son wire emitter arm MISSING`" | **STALE** | The producer emits it: `~/dev/perl5-son/lib/SoN/IR/Serialize/JSON.pm:140` `if ($op eq 'Coerce') {` with the comment "from_repr/to_repr are part of Coerce's content hash. Without emitting them the chalk loader rebuilds Coerce with UNDEF reprs". The gap the plan exists to close is closed. |
| ":86 "creates a `Coerce(Int->Num)` node in perl5-son FromOptree, wires it end-to-end"" (as future work) | **STALE** | Built: `_coerce_int_to_num`, `~/dev/perl5-son/lib/SoN/FromOptree.pm:133-140`. |
| ":89 "`Context.pm:1028`" (`_lower_coerce`) | **STALE (line)** | `sub _lower_coerce` at `lib/Chalk/Target/LLVM/Context.pm:1535`; dispatched from `:806`. |
| ":89 "JSON loader Coerce arm (`Serialize/JSON.pm:467`)" | **STALE (line, lands on unrelated code)** | :465-469 is the `FieldAccess` arm (`$args{field_index}`, `$args{field_stash}`), not Coerce. |
| ":184 "Coerce node + sitofp lowering shipped: Node/Coerce.pm; Context.pm:1019-1046" | **STALE (line)** | Same drift as above. `Node/Coerce.pm` still exists. |

### 8. `docs/plans/2026-07-20-coerce-vtable-consolidation-step1.md` — dangling forward reference

| claim | verdict | evidence |
|---|---|---|
| ":138 "TypedInvariant.pm:22, pinned by …"" | **STALE (line)** | `TypedInvariant.pm:18-26` is the `%OP_REQUIRED_REPR` preamble comment; the cited line is prose about which ops are listed, not the pin. The table itself begins at `:21`. Minor drift; target still present. |
| ":142 "the `Coerce(Int->Num)` node is the coercion-node work fenced to the runtime-MOP [pilot]"; ":172 "the `Coerce(Int->Num)` node the fix does not insert (invariant leg red; filed …)"" | **STALE** | It is inserted now — `_coerce_int_to_num` (producer `FromOptree.pm:133`). The fence is down. |
| ":18/:125 corpus-gate figures "148", ":140 "gate-green holds at 152" | **UNVERIFIABLE** | Corpus gate not run (reserved by another agent). Directionally these are plainly historical — later docs record 202→206→214→218 — but I did not measure, and do not assert. |

### 9. `docs/plans/2026-06-07-mdtest-corpus-format-draft.md` — one retired symbol, in a DECIDED SPEC

**Status line:** "DECIDED SPEC (all five open format questions resolved by
perigrin …)". A decided spec is high-trust, which is why even one stale symbol
is worth listing.

| claim | verdict | evidence |
|---|---|---|
| ":442 "the loader's `STAMP_TO_REPR` already maps `Boolean -> Bool`"" | **STALE (both halves)** | The symbol is retired, and the mapping it describes is exactly the `Bool`/`Boolean` translation that `2026-08-22-two-lattices-one-ir.md` deleted ("the stamp translation table is deleted (chalk `c38fed6e`)"). Today `Boolean` is a `%LOWERABLE_STAMP` member name-for-name (`Serialize/JSON.pm:30`). |

---

## Documents checked and found CLEAN (no stale load-bearing claim)

These were verified, not merely skimmed. Listing them matters: it tells the
owner where *not* to spend annotation effort.

### `docs/plans/2026-06-10-mop-migration-reaudit.md` — the best-aged document found

Two and a half months old and it still verifies almost exactly. Worth holding up
as the counter-example to finding 2 (same subject matter, opposite outcome).

| claim | verdict | evidence |
|---|---|---|
| "`Target::C::_generate_c_files($ir,$sa,$ctx)` is still the real C entry point" | CONFIRMED | `lib/Chalk/Bootstrap/Perl/Target/C.pm:1764`. |
| "`Target::C::generate($mop)` emits stub output only (`C.pm:1721-1726`)" | CONFIRMED | `method generate($mop)` at **:1722** — inside the cited range. |
| "which now *requires* `$ctx->mop()` (`C.pm:1853`)" | CONFIRMED | :1853 `// die "_generate_c_files requires \$ctx->mop() to be set; "`. Exact line. |
| "`Context::cfg_state()` (Context.pm:205-249)" | CONFIRMED | `method cfg_state()` at `lib/Chalk/Bootstrap/Context.pm:205`. Exact line. |
| "22 test files" consume `cfg_state` | CONFIRMED | `grep -rln "cfg_state" t/ \| wc -l` → **22**. Exact. |
| "`compat_class` … (17 test files)" | CONFIRMED | `grep -rln "compat_class" t/ \| wc -l` → **17**. Exact. |
| "15 `->body` readers remain in `lib/`" | CONFIRMED (±1) | `grep -rn -- "->body\b" lib/ \| wc -l` → **16**. One-site drift over 2.5 months. |
| "`Target/Perl.pm:75-77` 'kept alive transitionally for Target::C-via-Phase-7'" | CONFIRMED | Comment at `lib/Chalk/Bootstrap/Perl/Target/Perl.pm:76`. |
| "`rewrite_mop` is a follow-up" | CONFIRMED | `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm:48`. |
| "DCE is `run($graph,$factory)`, not `run($X)→$X`" (via CLAUDE.md) | CONFIRMED | `method run($input, $factory)` at `Optimizer/DCE.pm:22`. |

### `docs/research/2026-08-24-two-ir-architecture-alignment.md`

Self-verifies at 2 days old, as expected. Checked because it is the adjudicator
the brief leans on — if *it* were wrong, the rankings above would shift.

| claim | verdict | evidence |
|---|---|---|
| "418 `_emit()` calls in `Context.pm`" | CONFIRMED | `grep -c "_emit(" lib/Chalk/Target/LLVM/Context.pm` → **418**. Exact. |
| "zero passes … construct a `Chalk::IR::Graph`" in Optimizer/, Target/, IR/Schedule/ | CONFIRMED | `grep -rn "Graph->new"` over the three trees → **0**. |
| "`set_stamp` … called **zero times in all of `lib/`**" | CONFIRMED | 1 definition (`Node.pm:212`), 0 call sites. |
| "18 loader / 1 target `set_representation`" | CONFIRMED | 18 in `Serialize/JSON.pm`, 1 in `Target/LLVM/Context.pm`. |
| "`Pass.pm:2` ABOUTME states `run($X) -> $X`" | CONFIRMED | Verbatim at `lib/Chalk/Bootstrap/Optimizer/Pass.pm:2`; graph scope at :13-14. |
| "`ls lib/Chalk/IR/Node/` gives **87 node classes**" | **STALE (by 1, in 2 days)** | Now **88**. Noted for honesty, not as a defect — it illustrates how fast count claims rot in this tree. |

### `docs/plans/2026-08-21-type-vs-representation-seams.md`

Annotated on 2026-08-23 by `adab4d3a` ("annotate the seams plan with current
state"), which is the right treatment. Its *targets* all still exist; only line
numbers drifted. Per the brief these are "small defects":

| citation | verdict |
|---|---|
| `%_REPR_LLVM_TYPE` at `Context.pm:3036` | STALE (line) — actual **:3038**. Off by 2. |
| `%_COMPUTED_REPR` at `Serialize/JSON.pm:1285` | STALE (line) — actual **:1314**. Off by 29. |
| `%IR_OP_SOURCE_NAME` at `TypeLibrary.pm:382` | STALE (line, lands on unrelated code) — actual **:470**. :382 is the logical-operator signature loop (`for my $op ('&&','\|\|','//','and','or')`). Off by 88. |
| `Node.pm:41-56` / `:50` "representation is a per-use lowering decision" | CONFIRMED | The quoted text is at `Node.pm:41` (field comment opens) and the "per-use lowering decision" phrase at **:51**; `field $representation` at :56. Range holds. |
| `%RESULT_STAMP` at producer `FromOptree.pm:36-39` | CONFIRMED | Present. |

### `docs/plans/2026-08-22-two-lattices-one-ir.md` — the model treatment

Verified as the brief's reference example. Its post-resolution claims hold:
`Boolean` under `Str` (`TypeLibrary.pm:25`), `Any` deleted (0 occurrences),
stamp translation table deleted (`%STAMP_TO_REPR` → 0). The annotation pattern —
**status line rewritten to `RESOLVED <date>`, an `## Outcome — re-measured` block
placed above the original, and the original retained verbatim under `## ORIGINAL
FINDING …, retained for the record`** — is what findings 1-9 lack.

---

## Cross-cutting patterns (what to fix once rather than nine times)

**P1. Retired-symbol sweep.** Four symbols were renamed/deleted in the last
~10 days and their old names survive across documents. A single grep tells the
owner the full blast radius:

| retired symbol | replacement | docs still using the old name |
|---|---|---|
| `%STAMP_TO_REPR` | `%LOWERABLE_STAMP` (`Serialize/JSON.pm:30`) — a whitelist, **not** a rename map | 7 files: `2026-06-07-mdtest-corpus-format-draft.md`, `2026-07-19-ir-node-unification.md`, `2026-07-22-chalk-meta-type-coercion-registry.md`, `2026-07-22-representation-is-a-codegen-concern.md`, `2026-08-14-representation-is-the-targets-type-system.md`, `2026-08-22-two-lattices-one-ir.md` (correctly, as history), `2026-08-22-lattice-unification-audit.md` |
| `Any` (type) | `Unknown` (pessimistic top) / `List` (permissive signature position) | 9 files (list from `grep -rln`): incl. `2026-08-14-…`, `2026-08-13-node-type-and-typelibrary-as-authority.md`, `2026-08-22-lattice-unification-audit.md`, `2026-04-27-typelibrary-signature-audit-findings.md` |
| `Bool` (type) | `Boolean` | same cluster |
| `Chalk::IR::Shim` | deleted | `2026-04-25-audit-3-mop-ir-findings.md` and the April/May MOP plan family |

**Note on the producer:** `~/dev/perl5-son` still references `%STAMP_TO_REPR` in
**4 places across 2 files** (`lib/SoN/FromOptree.pm`, `lib/SoN/IR/Serialize/JSON.pm`)
— e.g. the `_coerce_int_to_num` comment "the wire stamp -> `%STAMP_TO_REPR`
arrives representation=Num on the chalk side". These are **code comments naming
a symbol that no longer exists in the consumer**. Out of scope for a docs audit,
but it is the same staleness class and I am naming it rather than deferring it
silently.

**P2. Line-number drift is pervasive and one class of it is dangerous.**
Of 23 `file:line` citations checked, **14 had drifted**. Most land within a few
lines of the intended target (harmless). Three land on *unrelated code*, which
is the serious class the brief names:

| citation | doc | lands on |
|---|---|---|
| `Node.pm:42` = `class()` | `2026-04-25-audit-3` | the `representation` lattice comment |
| `TypeLibrary.pm:382` = `%IR_OP_SOURCE_NAME` | `2026-08-21-seams` | logical-operator signatures |
| `Serialize/JSON.pm:467` = Coerce loader arm | `2026-07-22-slice-plan` | the `FieldAccess` arm |

No citation was found pointing at code that says the **opposite** of the claim
(the worst class). That is a genuine negative result, and it bounds the damage:
the drift here is navigational, not semantic.

**P3. Count claims rot fastest.** Every count checked that was >2 weeks old had
moved: 43→1, 45→27, 82→88, 61→0, 18→16, 4-dead→1-deleted-3-alive. Even the
2-day-old alignment audit's "87 node classes" is now 88. Counts in these
documents should be read as *timestamps*, not facts.

**P4. Nine documents are stale; the ones that aged well share a trait.**
`2026-06-10-mop-migration-reaudit.md` is 2.5 months old and near-perfect, while
`2026-04-25-audit-3` is 4 months old and near-totally stale. The difference is
not age — it is that the reaudit **cited stable anchors** (method names, ABOUTME
text, test-file counts) and the April audit cited **volatile ones** (line
numbers, per-file setter counts in a file under active edit).

---

## Method, and what was NOT checked

**Prioritization actually applied** (per brief step 2): all 229 files had date +
status extracted. From those, 21 were selected for claim-level verification on
three signals — (a) verdict-bearing status (`DESIGN`, `PLAN`, `DECIDED SPEC`,
`RESOLVED`, findings/audit), (b) subject-matter overlap with the areas known to
have moved (type lattice, representation, Coerce, MOP migration), (c) age >3
weeks. Pure measurement records with `MEASURED, reverted` status (the ~20
`2026-08-1x`/`2026-08-2x` producer-probe notes) were **deprioritized by design**:
they record what a probe showed on a named commit and are self-limiting.

**Explicitly not checked, and the residual risk:**

- **~188 documents were not claim-verified.** The heaviest unchecked cluster is
  the **Phase-7 / scheduler / codegen family** (~30 docs, `2026-05-21` through
  `2026-05-25`, several 80-90K). These are dense with file:line citations into
  `Target/` and `Actions.pm` — files that have since changed a great deal — so
  by pattern P2/P3 they very likely carry drift. I did not verify them and make
  **no claim** about them. If the owner wants a second pass, that cluster is the
  highest-expected-yield target.
- **The 5 `.txt` fixup-audit files** (`2026-05-*-fixup-audit-raw*.txt`) are raw
  tool output, not prose conclusions. Not checked; low misleading-risk by nature.
- **Corpus-gate floor numbers** in ~8 documents: **UNVERIFIABLE**. The gate was
  reserved by another agent and takes ~10 min. Reported as UNVERIFIABLE
  throughout rather than inferred from the doc chain.
- **`lib/Chalk/Target/`**: read-only greps only (`set_representation`, `_emit`,
  `_lower_coerce`, `_str_len_table` counts). No file in that tree was modified;
  another agent holds it.
- **Runtime behaviour**: nothing was executed. Every verdict rests on static
  measurement (`grep`, `ls`, `sed`, `git log`). Where a claim needed execution to
  settle, it is marked UNVERIFIABLE rather than guessed.

---

## Cross-references

- `docs/research/2026-08-24-two-ir-architecture-alignment.md` — the adjudicator
  for findings 4; independently spot-verified above and holding.
- `docs/plans/2026-08-22-two-lattices-one-ir.md` — the annotation-pattern model
  for findings 1, 5, 6, 9.
- `docs/plans/2026-06-10-mop-migration-reaudit.md` — supersedes finding 2's
  headline number; `CLAUDE.md` already carries that supersession, the document
  does not.
- `CLAUDE.md` "Plan Discipline (Chalk-specific)" — currently the ONLY place a
  reader is warned that the April-2026 MOP figures are obsolete. Findings 2 and 3
  are the argument for moving that warning onto the documents themselves.
