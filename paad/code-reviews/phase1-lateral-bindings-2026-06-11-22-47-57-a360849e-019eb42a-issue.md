# Agentic Code Review: 019eb42a (LLVM backend reads the MOP directly)

**Date:** 2026-06-11 22:47:57
**Branch:** phase1-lateral-bindings (issue scope: `1d32eae0^..a360849e`, 6 commits)
**Commit:** a360849e
**Design doc:** docs/plans/2026-06-11-llvm-reads-mop-directly.md

## Executive Summary

The MOP-direct migration (seal(), Call.class_name, registry from the sealed
MOP, corpus vocabulary, ClassInfo bridge deletion) is behaviorally sound:
all suites green at known baselines, corpus oracles byte-identical, the
ClassInfo deletion left zero dangling consumers in the LLVM tier. The
review found 2 execution-verified latent bugs and 1 nondeterminism hazard
in the new registry code, 1 serializer omission, and 5 cheap coverage gaps
— ALL FIXED in the follow-up commit. No Critical-at-runtime issues (every
failure mode was loud).

## Important Issues (all FIXED)

### [I1] Single-pass inheritance flatten loses grandparent methods
- `lib/Chalk/Target/LLVM.pm` `_flatten_inheritance` — sort-order single
  pass copied a parent's entry as it stood; a grandchild sorting before
  its parent (Kid < Mid < Top) lost Top's methods. Execution-verified
  ("available methods: []"). Pre-existing shape (the deleted scan had it
  unsorted = nondeterministic), made deterministic-wrong by this range.
- **Fixed:** memoized parents-first recursion with a cycle guard; RED
  grandparent subtest (names chosen child-sorts-before-parent) in
  llvm-mop-direct.t. Found by all 3 specialists.

### [I2] _method_body_root nondeterministic with multiple Returns; Unwind accepted
- `Graph::returns()` iterates a hash AND includes Unwind — `returns->[0]`
  picked an arbitrary root (verified 5/10 vs 5/10 across process runs).
- **Fixed:** exactly-one-Return contract enforced (GAP die), Unwind
  filtered; two-Returns die test added. Found by 2 specialists.

### [I3] _phaser_body_in_control_order misclassified input-closure nodes
- Collected statements from `nodes()` (input closure): a Call/Assign that
  is merely a statement's rhs counted as a body statement → spurious
  second chain head → false GAP on legitimate single-statement bodies.
  Execution-verified.
- **Fixed:** new `Graph::members()` (membership only); collection switched;
  unit subtest (store with a Call rhs collects exactly one statement).

### [I4] JSON serializer dropped Call.class_name
- The exact param_names/I3 omission pattern cited two lines above the gap:
  a round-tripped call lost its class (un-lowerable, content-hash change).
- **Fixed:** class_name in both extract and rebuild arms; serializer
  suites green.

### [I5] Coverage gaps (all closed)
1. has_default/default_value lowering via MOP::Field — untested (the whole
   suite stayed green with the path broken). → default-field lli subtest
   (Int:41).
2. MOP::Adjust list-order threading asserted shape, not order (identical
   statements). → distinct statements + control_in identity + which-is-
   second assertions.
3. class_name Call without mop → loud die untested. → Ghost subtest.
4. seal propagation tested on one class only. → multi-class subtest.
5. `use Chalk::IR::NodeFactory` missing in LLVM.pm (the
   %STATEMENT_EFFECT_OPS read was load-order-dependent: silently empty if
   nothing else loaded the factory). → explicit import.

## Suggestions (applied)

- Stale comments fixed (_scan_class_registry reference; the
  lower_with_elaboration doc comment now documents %opts/mop).
- The triple `(defined $mop ? (mop => $mop) : ())` guard collapsed —
  LLVMDriver guards undef internally; call sites pass `{ mop => $case_mop }`.

## Verified clean

Every lower/lower_with_elaboration caller matches the new signature; zero
dangling references to the three deleted bridge subs; all class-using
callers pass a sealed MOP; legacy Program-path ClassInfo consumers
(Actions/Target::Perl/C/StructPromotion/xs-*) untouched, compile, and pass
(owned by MOP-migration 4/4); corpus non-ir content byte-identical to the
pre-migration commit (nothing silently weakened); no production path seals
or lowers a parse MOP yet (parse-side seal wiring lands when the parse
pipeline grows an LLVM consumer). implicit-return.t test 15 fails
identically at the base commit — pre-existing.

## Review Metadata

- **Agents:** Logic & Correctness, Contract & Integration, Test Reality (3,
  parallel; concurrency/security lenses folded into Logic for this
  single-threaded compiler tier)
- **Raw findings:** 12 | **Verified:** 9 fixed + 3 cleared as
  checked-no-finding
- **Cross-agent agreement:** I1 by 3 (two live repros), I2 by 2
