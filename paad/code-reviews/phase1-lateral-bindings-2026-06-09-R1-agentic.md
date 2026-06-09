# Agentic Code Review: R1 (namespace move + Phase G gate hardening)

**Date:** 2026-06-09
**Branch:** phase1-lateral-bindings | **Window:** d3fb9069..39d0649b (R1)
**Method:** 3 specialists (logic/correctness, robustness/coverage, contract/integration) + verification.
**Scope:** the R1 foundation, AFTER the focused Tier-2 review already fixed B1/H1/H2/M1.

## Executive summary
The focused review fixed the triggered bugs; this deeper pass found LATENT foundation
bugs (none triggered by the current corpus, all VERIFIED against code) that will bite
R2/R3. Two classes: (a) INCOMPLETE-PROPAGATION / UNGUARDED-OPERAND in the emitter (the
same shape as the already-fixed H1 memcmp bug, recurring for other flags/operands), and
(b) the new Chalk::Target base is INCOHERENT (LLVM does not actually inherit it).

## Important issues (verified, latent, fix before R2)

### I1 — str_const global-name collision across contexts -> duplicate/undeclared @str_const_0
- File: lib/Chalk/Target/LLVM.pm (name alloc ~1339; emit main ~746, body ~554)
- Bug: `@str_const_<idx>` is indexed PER-context; each method body lowers in a fresh
  Context (counter restarts at 0), the main graph also starts at 0 -> two `@str_const_0`
  definitions in one module (duplicate symbol; lli rejects) or wrong-payload GEP.
- Latent: classes.t method bodies have no string constants today.
- Fix: unique per-module names (prefix body globals by class/method, or a shared counter).
- Confidence: 85.

### I2 — And/Or guard only the LHS; mixed-type RHS -> invalid phi
- File: lib/Chalk/Target/LLVM.pm `_lower_and` (~2061), `_lower_or` (~2124)
- Bug: G.7 dies unless lhs_repr eq Int, but there is NO RHS check; the merge phi is
  single-typed (LHS-derived). And(Int,Num) / And(Int,Bool) emits a phi mixing i64 with
  double/i1 = invalid LLVM. G.7 closed the LHS half of F8, left the RHS half open.
- Latent: logical.md L1/L2 are And/Or(Int,Int) only.
- Fix: guard rhs_repr identically (or route both through _ensure_i1 + coerce to a common
  type); add an And(Int,Bool)/And(Int,Num) test. (Two specialists found this.)
- Confidence: 80.

### I3 — %StrPair propagated but never consumed -> undeclared type
- File: lib/Chalk/Target/LLVM.pm (%StrPair emit gated at ~376 on method-returns-Str;
  _need_strpair SET at 3503/3635/3811, propagated 486/542, but NO post-class emit)
- Bug: a Str FIELD READ in a non-Str-returning method emits %StrPair* refs, but %StrPair
  is declared only when some method RETURNS Str -> undeclared type -> invalid LLVM. Same
  incomplete-propagation class as the fixed H1 memcmp bug, for _need_strpair.
- Latent: no current method reads a Str field while returning non-Str.
- Fix: add a post-class %StrPair re-emit guarded by an _strpair_emitted flag (mirror memcmp).
- Confidence: 70.

### I4 — Chalk::Target::LLVM does NOT isa Chalk::Target -> the base lower contract is fiction
- File: lib/Chalk/Target/LLVM.pm:3 (plain `package`, no `:isa`) vs lib/Chalk/Target.pm
  (lower stub documented "for typed-IR backends e.g. LLVM")
- Bug (runtime-verified: LLVM->isa(Chalk::Target) = NO): the new base unifies only the
  Bootstrap family (which never needed `lower`) and gives nothing to LLVM (which has its
  own class-method `lower`). The base's `lower` is dead surface; the F2-iface
  reconciliation is nominal, not real.
- Fix: either make LLVM `:isa(Chalk::Target)` and actually override `lower` (note: it is
  class-method style; converting to instance needs care), OR remove the `lower` stub +
  the "typed-IR backends" claim and document LLVM as intentionally outside the hierarchy
  until migrated.
- Confidence: 95.

### I5 — Bootstrap targets now inherit an alien lower die-stub
- File: lib/Chalk/Target.pm:30-32 (lower stub) inherited via the Bootstrap::Target isa alias
- Bug (runtime-verified: Perl::Target::Perl->can(lower) now YES, was absent): the base
  conflates two tiers (lower for LLVM; generate/generate_distribution for Bootstrap);
  each subclass inherits stubs for the other tier. Confused base.
- Fix: split into a Bootstrap-tier base (generate*) and a typed-IR base (lower); LLVM
  extends the latter (resolves I4 too).
- Confidence: 90.

## Coverage gaps (real — guards unproven against a positive)
- CG1: G.1 MISCOMPILE classification tested ONLY via a monkey-patched LLVMDriver mock; no
  real graph drives a real lowered-but-lli-rejected MISCOMPILE through the unmocked path
  (g1-miscompile-classification.t:79-103). Conf 90.
- CG2: G.2 libperl guard strip-fix `s/^...constant...c"...$//mg` strips the WHOLE line; a
  libperl symbol on a line that also has constant+c" would be stripped (leak slips).
  Untriggerable today (emitter only emits those on data lines) but brittle; the test does
  not pin it. Conf 75.
- CG3: G.6 _require_repr: the highest-risk sites (the 3 Phi sites, New/MethodCall/
  FieldAccess/FieldWrite, the ElaboratedContext path) are UNTESTED; the Ternary-branch
  guards are unreachable (operand lowering dies first) and Test 7 passes on the WRONG
  error message. Conf 85.

## Separate pre-existing bug surfaced (NOT caused by R1)
### P1 — Golden enshrines a `no warnings` -> `use warnings` inversion
- lib/Chalk/Bootstrap/Target.pm:6 is `no warnings 'experimental::class'` but the golden
  (the codegen OUTPUT) shows `use warnings`. Root cause: UseDeclaration (Actions.pm ~614)
  fails to propagate the `no` keyword into UseInfo->keyword (stays 'use'). The byte-compat
  golden now certifies the buggy output. File a parser issue; this is in the known-baseline
  byte-compat failures, NOT an R1 regression. Conf 88.

## Cleared (verified OK)
- G.5 flag propagation list complete + llvm-method-body-needs.t drives the real path
  (memcmp double-declare guard tested). G.1 three-way classification logic sound. G.2 strip
  sound for the CURRENT emitter output. G.6 alias works. G.7 _lower_not/_ensure_i1
  consistent. Namespace move mechanically complete (loader, inner packages, no stale refs
  in lib/t/script). No subclass loses a concrete method (old base = stubs only). The "153
  consumers" figure was actually ~5 real subclasses.
