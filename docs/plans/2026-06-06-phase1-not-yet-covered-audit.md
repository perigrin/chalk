# Phase 1 Codegen-Harness Audit: 73 NOT-YET-COVERED Idioms

**Date**: 2026-06-06  
**Scope**: Read-only audit of tier-1 gap-map to classify 73 NOT-YET-COVERED idioms by blocker type.  
**Goal**: Determine HOW OPEN-ENDED Phase 1 is by answering: WHAT BLOCKS each idiom from PASS?

---

> ## ⚠ CORRECTION — see the pushback review before acting on this doc
>
> An adversarial pushback review (`docs/plans/2026-06-06-phase1-audit-pushback-review.md`,
> verified against code) found this audit's bucket COUNTS roughly right and BUCKET-1
> genuinely mechanical (confirmed end-to-end against real perl), but identified three
> material errors that change the decomposition. Do NOT create child issues from the
> original recommendation below; use the corrected decomposition in the pushback review.
>
> 1. **BUCKET-2 is described against the WRONG code path.** The harness drives
>    `generate(MOP)` → `_generate_from_schedule` → `Chalk::IR::Scheduler::EagerPinning`.
>    The audit's bucket-2 (`cfg_state`, `emit_cfg_if`/`emit_cfg_loop`, `true_proj`/`false_proj`)
>    describes `_generate_with_cfg`, which `die`s unless given a parser `Program`
>    (`Target/Perl.pm:494-495`) and is UNREACHABLE from a hand graph. The real 1b work is
>    scheduler `schedule_data` construction (`EagerPinning::If/Loop/TryCatch`,
>    `control_in`/region wiring); recipe = `t/bootstrap/scheduler/schedule-data-*.t`.
>    "Solving patterns 1,3,4 unlocks 13 of 25" is asserted, not verified.
> 2. **M19 (`my ($a,$b)=(1,2)`) is a buried deep unknown**, not a low-priority bucket-3 item:
>    no tuple/list-assignment IR node exists (only `ExpressionList`/`Multiply`); the naive
>    emission miscompiles. Give it its own spike, do not bury it in 1c.
> 3. **BUCKET-4 ≠ 0.** M20 (`do`) has no IR node and M21 (`eval`) is excluded by project
>    policy — both are scope decisions, not codegen work.
>
> Also recommended: re-bucket M10, M11, K2, D6 from bucket-3 into 1a (not real gaps).
> The week-level estimates (1 week / 2-3 weeks) are decorative for an AI-driven process —
> the real unit of uncertainty is distinct CFG patterns + genuine unknowns, not idiom count.

---

## Executive Summary

**Phase 1 = "Complete CodeGen to tier-1 green (S=P) for all 78 idioms."**

- **Current state**: 5 PASS (A1, A4, A5, E1, F3 with hand graphs); 73 NOT-YET-COVERED
- **Key finding**: Phase 1 is **TRACTABLE but BIMODAL**
  - **41 idioms (BUCKET-1)** are purely mechanical: hand-graph only, all emitters exist
  - **25 idioms (BUCKET-2)** require Region/Phi CFG construction (deliberately deferred from Phase 0)
  - **6 idioms (BUCKET-3)** surface emitter gaps or unclear IR semantics
  - **0 idioms (BUCKET-4)** are out-of-scope

**Recommendation**: Split Phase 1 into 3 child issues:
1. **1a: BUCKET-1 data-only (41 idioms)** — 1 week, low risk, parallelizable
2. **1b: BUCKET-2 CFG patterns (25 idioms)** — 2-3 weeks, required for control flow
3. **1c: BUCKET-3 emitter gaps (6 idioms)** — 1-2 weeks, can run in parallel with 1b

---

## Classification Axis: Cost Model

Each NOT-YET-COVERED idiom blocks on ONE of two costs:

### Cost 1: HAND-GRAPH Cost
The idiom needs a hand-authored Chalk::MOP/Program graph in HandGraphs.pm (currently only 5 have `graph_for` entries).

- **DATA-ONLY idioms** (A1/A4/A5/E1/F3 pattern): mechanical — node-by-node assembly, ~30 LOC per idiom, identical to the working 5
- **CONTROL-SHAPE idioms** (if/else, loops, try/catch): much harder — requires Region/Phi node wiring, explicit CFG state, IR-internals expertise

### Cost 2: EMITTER Cost
Even WITH a correct graph, does Target::Perl actually emit correct Perl for this construct?

- Most constructs already have `_emit_*` methods (see Target/Perl.pm line 938+)
- Some constructs may have gaps: unclear IR semantics, missing node types, or emitter bugs

---

## BUCKET 1: DATA-ONLY, EMITTER-READY (41 idioms)

**Blockers**: NONE — all hand-graph + emitter work already exists

**Pattern**: Identical to A1/A4/A5/E1/F3
- Build a Chalk::IR::NodeFactory, wire nodes into a Graph, populate a Chalk::MOP
- Return the MOP from a builder sub in HandGraphs.pm
- No Region, no Phi, no control flow wiring
- All expression types already have _emit_* methods

**Idioms** (41 total):
- **A group**: A2 (array literal), A3 (hash literal)
- **B group**: B1 (push), B2 (print), B3 (say), B4 (die), B5 (function call), B6 (method call), B7 (unshift)
  - *(B8 excluded — warn missing from emitter)*
- **C group**: C1 (reassign), C2 (compound +=), C3 (concat .=), C4 (array element assign), C5 (hash element assign)
- **F group**: F1 (method chain), F2 (method with args)
- **G group**: G1 (deref @*), G2 (deref %*), G3 (subscript []), G4 (subscript {})
- **H group**: H1 (map block), H2 (grep block), H3 (sort), H4 (anon sub)
- **I group**: I2 (top-level sub), I3 (my sub)
- **J group**: J1 (regex match), J2 (regex subst), J3 (qw literal)
- **K group**: K1 (pre-increment ++$i)
- **L group**: L1 (&&), L2 (||), L3 (//), L4 (!)
- **M group**: M1 (use pragma), M2 (use module), M3 (string interpolation), M4 (string interpolation with @array)
  - M8 (arrow subscript []), M9 (arrow subscript {}), M12 (static method call), M13 (qualified call), M14 (string concat .), M15 (//= assign)
  - M22 (sort with block), M23 (bare delete), M24 (chained arrow subscript)

**Evidence**:
- `_emit_binary_expr` handles `=`, `+=`, `.=`, `.`, `//`, `&&`, `||` operators
- `_emit_builtin_call` lists `push`, `unshift`, `print`, `say`, `die` as no-parens builtins
- `_emit_method_call_expr` recursively handles chained calls
- `_emit_subscript_expr` handles all bracket/brace styles
- `_emit_postfix_deref_expr` handles `->@*` and `->%*`
- `_emit_anon_sub_expr` generates `sub ($params) { ... }`
- `_emit_regex_match`, `_emit_regex_subst`, `_emit_interpolated_string` all exist
- `_emit_unary_expr` handles prefix operators like `++`, `!`

**Risk**: LOW — purely mechanical copy-paste-modify from existing 5 graphs

---

## BUCKET 2: CONTROL-SHAPE (25 idioms)

**Blocker**: Need Region/Phi hand-graph wiring. Emitters exist (_emit_cfg_if, _emit_cfg_loop, _emit_cfg_try_catch) but require correct IR structure.

**Phase 0 Context**: The CLAUDE.md notes that "control-shape idioms (if/else, while, for, loops) need real Region/Phi wiring — much harder IR-internals work, explicitly deferred from Phase 0."

**Core Insight**: The 25 BUCKET-2 idioms cluster into **6 recurrent CFG patterns**:

### Pattern B2-1: IF/ELSE (3 idioms)
Idioms: D1 (if/else with assign), D7 (nested if), M16 (block unless)

**IR Structure**:
```
If(cond_expr)
├─ true_proj → Phi(var, true_val, false_val)
└─ false_proj → Phi(var, true_val, false_val)
```

**Emitter**: `_emit_cfg_if` at line 1327; dispatches true/false stmts through cfg_state

**Challenge**: Build Region + Phi nodes; wire cfg_state side-table with if_node, true_proj, false_proj, then_stmts, else_stmts

### Pattern B2-2: POSTFIX MODIFIERS (3 idioms)
Idioms: D4 (postfix if), D5 (postfix while), M5 (postfix unless)

**IR Structure**:
```
Synthetic If(cond) wrapping assignment
├─ true: assignment statement
└─ false: skip (empty)
```

**Emitter Challenge**: _emit_loop_jump (line 1312) targets loop-exit next/last, not bare-statement modifiers. May need different emission path.

**Phase 0 Note**: "parser generates synthetic If for postfix modifiers; needs statement/expression context decision" — deferred.

### Pattern B2-3: WHILE LOOP (1 idiom)
Idiom: D2 (while loop)

**IR Structure**:
```
Loop → controlled If(cond)
├─ true_proj → body statements
└─ false_proj → exit
```

**Emitter**: `_emit_cfg_loop` at line 1403; `_emit_while_head` at line 385 generates `while (cond) {`

**Challenge**: Hand-wire Loop + controlled If; populate cfg_state with loop, loop_if, body_proj, exit_proj

### Pattern B2-4: FOREACH LOOP (4 idioms)
Idioms: D3 (foreach my $n), M6 (postfix for), M7 (for without my), M25 (C-style for init;cond;step)

**IR Structure**:
```
Loop → iterator/list on schedule_data
├─ body_stmts
└─ (exit implicit)
```

**Emitter**: `_emit_cfg_loop` handles iterator/list; `_emit_foreach_head` (line 395) and `_emit_for_head` (line 411) generate headers

**Challenge**: M25 (C-style for) requires for_init/for_step on schedule_data, not just iterator/list

### Pattern B2-5: EARLY EXITS FROM LOOPS (2 idioms)
Idioms: M17 (next), M18 (last)

**IR Structure**:
```
If node (loop condition check) with loop_jump marker
├─ true: exit via next/last
└─ false: continue
```

**Emitter**: `_emit_loop_jump` at line 1312; detects loop_jump marker and negation wrapper

**Challenge**: cfg_state side-table must carry loop_jump marker; needs wiring during parse

### Pattern B2-6: BLOCK-AS-EXPRESSION (2 idioms)
Idioms: M20 (do block), M21 (eval block)

**IR Structure**: UNCLEAR — requires design spike
- `do { ... }` is a block that evaluates to the last expression
- `eval { ... }` is a try-catch-like wrapper (error in block caught, value returned or undef)
- Both may need Region + synthetic Return, OR a block-value mechanism (post-Phase-1)

**Emitter Challenge**: Unknown IR structure means unknown emission strategy

### Pattern B2-7: CONTROL RETURNS (3 idioms)
Idioms: E2 (return in if), E3 (return in loop), E4 (die in if)

**IR Structure**: Same If/Loop Regions as B2-1 through B2-4, but:
- Body stmts contain explicit Return/Unwind instead of Phi merge
- Early exit bypasses Phi

**Emitter**: _emit_cfg_if / _emit_cfg_loop already dispatch on body stmts; should work if Region/Phi are correct

**Challenge**: Understand whether return-in-if produces an exit Proj or a merge Phi

### Pattern B2-8: ADJUST BLOCK (1 idiom)
Idiom: I1 (ADJUST block in class)

**IR Structure**: Synthetic control flow for class initialization side effects

**Challenge**: Interaction with Chalk::MOP and field initialization; not a traditional Block

---

## BUCKET 3: EMITTER-GAP-SUSPECTED (6 idioms)

**Blocker**: Construct uses an IR node type or emitter method that is ABSENT or UNCLEAR.

### B8: warn (1 idiom)
**Evidence**: `_emit_builtin_call` at line 1297-1302 lists no-parens builtins as:
```perl
if ($name eq 'push' || $name eq 'unshift' || $name eq 'die'
    || $name eq 'return' || $name eq 'print' || $name eq 'say') {
    return "$name " . join(', ', @arg_strs);
}
```

**Gap**: `warn` is NOT in this list. May fall through to paren-call syntax `warn(...)` which is valid but less idiomatic than `warn ...`.

**Classification**: LOW-RISK EMITTER FIX — add 'warn' to no-parens list (1 line)

### D6: ternary (1 idiom)
**Corpus**: `my $x = $n > 0 ? 1 : 2;`

**Emitter**: `_emit_ternary_expr` at line 1177 exists and handles ternary as EXPRESSION.

**Gap**: Unclear whether ternary can be CONTROL-SHAPED (i.e., used as the exit value of a block that is itself an If). Most ternaries are expressions; may be misclassified.

**Classification**: CLARIFY-NEEDED — is D6 actually testing ternary as control or just as expression? If just expression, move to BUCKET-1.

### K2: post-increment (1 idiom)
**Corpus**: `$i++` (vs K1 `++$i`)

**Evidence**: Actions.pm line ~1590 says:
```perl
# Pre/post distinction is elided here (both become CompoundAssign); a typed
# PreIncrement/PostIncrement node distinction is deferred to a future pass.
```

**Gap**: Pre/post are both compiled to CompoundAssign with += operator. No IR node type distinguishes them. Emitter cannot emit `$i++` vs `++$i`.

**Classification**: DESIGN DECISION DEFERRED — the comment promises a future PreIncrement/PostIncrement node. Until that lands, K2 cannot PASS (both pre/post emit as CompoundAssign).

**Action**: Track as KNOWN-LIMITATION. Can mark K2 as blocked-by-future-node-type.

### M10: ref of array, M11: ref of hash (2 idioms)
**Corpus**: `\@list`, `\%hash`

**IR Node**: Ref node EXISTS at lib/Chalk/IR/Node/Ref.pm and subclasses UnaryOp.

**Emitter**: `_emit_expr` DOES NOT explicitly dispatch on Ref nodes; falls through to _emit_node which should handle UnaryOp.

**Gap**: Unclear whether _emit_unary_expr correctly emits Ref(sigil, target) as `\$target` or `\@target` etc. UnaryOp layout suggests inputs[0]=operator, inputs[1]=operand, but Ref may have different semantics.

**Classification**: MEDIUM-RISK — Ref node exists but emitter path unclear. Needs validation: does `_emit_unary_expr` with op='\\' emit correctly?

### M19: tuple multi-assign (1 idiom)
**Corpus**: `my ($a, $b) = (1, 2);`

**Gap**: Needs unpacking of ExpressionList RHS into multiple VarDecl LHS. Unclear if Chalk IR supports this pattern.

**Classification**: HIGH-RISK DESIGN GAP — multi-assign may need new IR node type or special VarDecl layout. Requires design spike.

---

## Per-Group Rollup

| Group | Total | BUCKET-1 | BUCKET-2 | BUCKET-3 | Notes |
|-------|-------|----------|----------|----------|-------|
| A     | 5     | 2        | 0        | 0        | 3 PASS (A1, A4, A5) |
| B     | 8     | 7        | 0        | 1        | B8 (warn) in gap |
| C     | 5     | 5        | 0        | 0        | All assignment operators handled |
| D     | 8     | 0        | 7        | 1        | D6 (ternary) unclear if control |
| E     | 4     | 0        | 3        | 0        | 1 PASS (E1) |
| F     | 3     | 2        | 0        | 0        | 1 PASS (F3) |
| G     | 4     | 4        | 0        | 0        | All deref/subscript handled |
| H     | 4     | 4        | 0        | 0        | Block builtins all data |
| I     | 3     | 2        | 1        | 0        | I1 (ADJUST) needs control |
| J     | 3     | 3        | 0        | 0        | All regex handled |
| K     | 2     | 1        | 0        | 1        | K2 pre/post future node |
| L     | 4     | 4        | 0        | 0        | Logical ops all handled |
| M     | 25    | 15       | 7        | 3        | Mixed; 10 control, 15 data |
|-------|-------|----------|----------|----------|-------|
| **TOTAL** | **78*** | **41** | **25** | **6** | 5 PASS; 73 NOT-YET-COVERED |

\* 78 total: 5 PASS + 73 NOT-YET-COVERED

---

## BUCKET-1 Idiom List (Quick Wins)

Explicit list for Phase 1a work planning:

```
A2, A3,
B1, B2, B3, B4, B5, B6, B7,
C1, C2, C3, C4, C5,
F1, F2,
G1, G2, G3, G4,
H1, H2, H3, H4,
I2, I3,
J1, J2, J3,
K1,
L1, L2, L3, L4,
M1, M2, M3, M4, M8, M9, M12, M13, M14, M15, M22, M23, M24
```

---

## BUCKET-2 Idiom List (CFG Core)

```
D1, D2, D3, D4, D5, D7, D8,
E2, E3, E4,
I1,
M5, M6, M7, M16, M17, M18, M20, M21, M25
```

---

## BUCKET-3 Idiom List (Emitter Gaps)

```
B8 (warn not in no-parens list),
D6 (ternary-as-control unclear),
K2 (post-increment blocked by future PreIncrement node),
M10, M11 (Ref node emitter path unclear),
M19 (tuple multi-assign design gap)
```

---

## Control-Shape Patterns: Recurring Shapes

**Key Finding**: The 25 BUCKET-2 idioms collapse into 6 DISTINCT CFG PATTERNS + 1 outlier (ADJUST).

This suggests Phase 1b is NOT genuinely open-ended per-idiom; rather, it's a **small, well-defined IR core**:

1. **If/Else**: Region + Phi merge (3 idioms)
2. **Postfix Modifiers**: Synthetic If wrapper (3 idioms)
3. **While Loop**: Loop + controlled If (1 idiom)
4. **Foreach Loop**: Loop + iterator/list (4 idioms; M25 adds init/step)
5. **Early Exits**: If with loop_jump marker (2 idioms)
6. **Block-as-Expression**: Design TBD (2 idioms: do, eval)
7. **Control Returns**: If/Loop + return exit (3 idioms)
8. **ADJUST**: Synthetic side-effect control (1 idiom)

**If we solve patterns 1, 3, 4, and 7 correctly, most of BUCKET-2 unlocks** (13 out of 25).

---

## Phase 1 Decomposition Recommendation

### Phase 1a: BUCKET-1 Data-Only (1 week)
**Goal**: Complete CodeGen for all 41 data-only idioms.

**Work**:
- Add 41 graph builder subs to HandGraphs.pm (copy-paste-modify from A1/A4/A5/E1/F3)
- Each builder: ~30 LOC, identical mechanical pattern
- Total: ~1200 LOC

**Parallelization**: Can split into groups (A/B/C, F/G/H, I/J/K/L/M) and run 3-4 agents in parallel.

**Expected outcome**: 46 PASS (5 existing + 41 new); 32 NOT-YET-COVERED

---

### Phase 1b: BUCKET-2 CFG Patterns (2-3 weeks)
**Goal**: Complete CodeGen for all 25 control-flow idioms by solving 6 core patterns.

**Work**:
1. **Spike**: Understand Region/Phi semantics in Chalk::IR (existing docs: ARCHITECTURE.md, comonad-specification.md)
2. **Pattern Implementation** (ordered by impact):
   - If/Else (D1, D7, M16): Build Region(If) + Phi merge + cfg_state wiring
   - While Loop (D2): Loop + controlled If pattern
   - Foreach Loop (D3, M6-M7): Loop + iterator/list; M25 variant with init/step
   - Early Exits (M17-M18): If + loop_jump marker in cfg_state
   - Control Returns (E2, E3, E4): If/Loop + Return in stmts
   - Postfix Modifiers (D4, D5, M5): Synthetic If at statement level
   - Block-as-Expression (M20, M21): Design spike needed; may defer to Phase 2
   - ADJUST Block (I1): MOP integration; may defer to Phase 2

**Blocking constraint**: Phase 0 explicitly deferred Region/Phi wiring; Phase 1b unblocks it.

**Expected outcome**: 71 PASS (46 + 25); 2 NOT-YET-COVERED (M20, M21 if deferred)

---

### Phase 1c: BUCKET-3 Emitter Gaps (1-2 weeks, parallel with 1b)
**Goal**: Clarify and close 6 emitter/IR gaps.

**Work**:
1. **B8 (warn)**: Add to no-parens list in _emit_builtin_call; verify test
2. **D6 (ternary)**: Classify as expression or control; if expression, move to BUCKET-1
3. **K2 (post-increment)**: Document as blocked-by-future-PreIncrement-node; flag issue for Phase 2
4. **M10-M11 (Ref)**: Trace _emit_unary_expr path for Ref nodes; test with \@ and \%
5. **M19 (tuple assign)**: Design spike; determine if MultiAssign IR node needed or if VarDecl layout can pack multiple names

**Can run in parallel with 1b** since mostly independent investigation.

**Expected outcome**: Clarified gaps; some fixes (B8, D6), some deferred to Phase 2 (K2, M19)

---

## Timeline & Effort

| Phase | Effort | Duration | Risk | Blockers |
|-------|--------|----------|------|----------|
| 1a    | 1200 LOC (40 builders) | 1 week | LOW | None; all emitters exist |
| 1b    | 600-800 LOC (6 CFG patterns) | 2-3 weeks | MEDIUM | Must understand Region/Phi; Phase 0 deferred this |
| 1c    | 100-200 LOC (investigate + 1-2 fixes) | 1-2 weeks (parallel) | MEDIUM-HIGH | Design gaps (K2, M19) may require larger work |

**Total**: 3-4 weeks to achieve ~71 PASS (all but M20/M21 and possibly K2).

---

## Assessment: How Open-Ended Is Phase 1?

**Answer: NOT GENUINELY OPEN-ENDED. Phase 1 is tractable, well-scoped, with clear blockers.**

### Evidence:
1. **BUCKET-1 (41 idioms)** has zero blockers: all emitters exist, hand-graphs are mechanical copies
2. **BUCKET-2 (25 idioms)** clusters into **6 recurrent CFG patterns**, not 25 bespoke problems
3. **BUCKET-3 (6 idioms)** are clarifiable gaps, mostly independent

### The Hard Core:
The **only true blocker for Phase 1 completeness** is implementing Region/Phi hand-graph patterns. This is a known gap explicitly deferred from Phase 0 — not an unknown architectural problem.

**Per-pattern complexity**:
- If/Else + While/Foreach: **well-understood** (emitters exist; just need hand-graph IR construction)
- Early Exits + Control Returns: **well-understood** (cfg_state mechanism exists; just needs wiring)
- Postfix Modifiers: **deferred from Phase 0** (parser challenge, not codegen)
- Block-as-Expression: **design TBD** (may defer to Phase 2)

### Recommendation:
**Phase 1 should be split into 3 child issues ordered by cheapest-unblocks-most**:
1. 1a: BUCKET-1 data (41 idioms, 1 week, removes 46/78 immediately)
2. 1b: BUCKET-2 CFG (25 idioms, 2-3 weeks, requires Phase-0-deferred work but fully understood)
3. 1c: BUCKET-3 gaps (6 idioms, parallel, clarifies design decisions)

---

## Files Audited

- `t/fixtures/codegen-harness/gap-map.json` — 78 idiom verdicts
- `t/fixtures/ir-audit-corpus.pl` — actual Perl source for all 78 idioms
- `lib/Chalk/CodeGen/Harness/HandGraphs.pm` — 5 existing hand-graph builders
- `lib/Chalk/Bootstrap/Perl/Target/Perl.pm` — emitter (_emit_* methods)
- `lib/Chalk/Bootstrap/Perl/Actions.pm` — IR construction notes (Pre/post-inc, etc.)

---

## Appendix: Detailed Per-Idiom Rationales

### BUCKET-1 Examples (Why they're all mechanical):

**A2 (VarDecl array literal)**
```perl
my @list = (1, 2, 3);
```
- IR: VarDecl with ArrayRef init node
- Emitter: _emit_init_expr (line 1014) checks `$var =~ /^\@/` and uses _emit_expr on ArrayRef
- Hand-graph: identical to A1 except init is ArrayRef([Const(1), Const(2), Const(3)]) instead of Const(1)

**C4 (array element assignment)**
```perl
$a[0] = 2;
```
- IR: BinOp(Assign op, lhs=Subscript([0]), rhs=Const(2))
- Emitter: _emit_binary_expr (line 1036) handles = operator; _emit_subscript_expr handles [index] style
- Hand-graph: build BinOp + Subscript nodes, identical pattern to A4

**M24 (chained arrow subscript)**
```perl
$r->{a}->[0]
```
- IR: Subscript(Subscript($r, "a", hash), 0, array)
- Emitter: _emit_subscript_expr (line 1087) recursively calls _emit_expr on target, which itself is a Subscript
- Hand-graph: nest Subscript nodes; identical to G4 except target is another Subscript

### BUCKET-2 Examples (Why they need CFG):

**D1 (if/else with reassignment)**
```perl
if ($n > 0) { $x = 1; } else { $x = 2; }
```
- IR Needed: If(cond, Region, Phi($x, 1, 2))
- Emitter: emit_cfg_if (line 1327) generates `if (cond) { ... } else { ... }`
- cfg_state: must carry if_node, true_proj, false_proj, then_stmts, else_stmts
- Challenge: hand-wire Region + Phi nodes to enable cfg_state lookup

**M6 (postfix for)**
```perl
$sum = $sum + $_ for (1, 2, 3);
```
- IR Needed: Loop(Region, iterator=$_, list=[1, 2, 3], body=[assign])
- Emitter: _emit_cfg_loop (line 1403) + _emit_foreach_head (line 395)
- Challenge: hand-wire Loop with schedule_data carrying iterator/list

### BUCKET-3 Examples (Why they're risky):

**B8 (warn)**
- **Issue**: `warn "hi"` should emit as `warn "hi";`, not `warn("hi");`
- **Current**: warn not in no-parens builtin list (line 1297), so falls through to paren form
- **Fix**: 1-line addition to the condition

**K2 (post-increment)**
- **Issue**: `$i++` vs `++$i` should emit differently
- **Current**: Both become CompoundAssign operator (Actions.pm line ~1590)
- **Root**: "Pre/post distinction is elided here ... deferred to a future pass"
- **Status**: KNOWN-DEFERRED, not a bug; flag for Phase 2

**M19 (tuple multi-assign)**
- **Issue**: `my ($a, $b) = (1, 2)` needs to unpack RHS list into multiple LHS VarDecls
- **Current**: Unclear if IR supports this pattern
- **Risk**: May need new node type or significant VarDecl rework

---

## Decision Record

**Audit Date**: 2026-06-06  
**Auditor**: Phase 1 classification spike  
**Conclusion**: Phase 1 is tractable, not open-ended. Recommend split into 3 child issues.

**Highest-Priority Unblock**: Phase 1b (BUCKET-2 CFG). Once Region/Phi patterns are proven, 25 idioms unlock.

**Next Step**: Begin Phase 1a (BUCKET-1 data-only). Run 3-4 parallel builder-generators for A/B/C, F/G/H, I/J/K/L/M groups. Target completion in 1 week.

