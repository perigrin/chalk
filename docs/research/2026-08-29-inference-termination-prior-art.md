# Inference termination: the established theory, and what chalk actually has

Research date: 2026-08-29. Sources retrieved and quoted; retrieval failures marked.

## The question

Chalk's type inference is a set of passes over a Sea-of-Nodes graph, run to a
fixpoint. Termination has been argued PER PASS, by hand. This document replaces
those hand-built arguments with the standard theory, and measures chalk's
current code against it.

The provoking bug, 2026-08-29: `_is_narrowed` was loosened so `Scalar` could be
refined downward. The loop HUNG -- a `DefinedOr` over `(Undef, Int)` joins to
`Scalar`, is revisited, re-joins to `Scalar`, forever. Corpus case `logical.md`
L3b reached iteration 457,642 before being killed. The fix (commit `6db5dcdc`)
made writes conditional on an actual change rather than one-write-per-node.

**The short version: the fix is correct, it is the standard one, and it is half
of Kildall's 1973 termination proof. But chalk implements only one of that
proof's two halves, and the missing half is why the loop hung in the first
place.**

---

## Part 1: the standard theory

### 1.1 Kleene's fixed-point theorem

Moller & Schwartzbach, *Static Program Analysis*, ch. 3
(https://cs.au.dk/~amoeller/spa/3-lattices-and-fixpoints.pdf), verbatim:

> **Kleene's fixed-point theorem**
> In a complete lattice with finite height, every monotone function f has a
> unique least fixed-point: `lfp(f) = ⨆ᵢ≥₀ fⁱ(⊥)`

Proof, verbatim:

> - Clearly, ⊥ ⊑ f(⊥)
> - Since f is monotone, we also have f(⊥) ⊑ f²(⊥)
> - By induction, fⁱ(⊥) ⊑ fⁱ⁺¹(⊥)
> - This means that ⊥ ⊑ f(⊥) ⊑ f²(⊥) ⊑ ... **is an increasing chain**
> - **L has finite height, so for some k: fᵏ(⊥) = fᵏ⁺¹(⊥)**

### 1.2 What each condition buys

| Condition | Buys | Does NOT buy |
|---|---|---|
| **Monotonicity** | That the iterates form a **chain at all**. `⊥ ⊑ f(⊥)` plus monotonicity gives `fⁱ(⊥) ⊑ fⁱ⁺¹(⊥)` by induction. Without it the sequence can oscillate forever in a finite lattice. | Termination. A monotone function on an infinite-height lattice ascends forever. |
| **ACC / finite height** | That the chain **cannot be infinite**, so it stabilizes at finite k. Finite height is strictly stronger than ACC (it bounds k, giving the complexity result). ACC alone suffices for termination. | Correctness or precision. |
| **Kleene** | The **constructive** result: the limit is reached by iterating from ⊥, and it is the **least** fixed point. | -- |
| **Tarski** | That a fixed point **exists** on any complete lattice with monotone f, *without* finite height -- but non-constructively (as `⊓red(f)`), so it gives no algorithm. | An algorithm. |

### 1.3 THE CRITICAL POINT: the update discipline is part of the proof

This is the direct answer to "does monotonicity + finite height guarantee
termination REGARDLESS of the update discipline?"

**No. The discipline is load-bearing, and Kildall's own termination proof turns
entirely on it.**

Kildall, "A Unified Approach to Global Program Optimization," POPL '73,
pp. 194-206. Full text retrieved from NPS Calhoun
(https://calhoun.nps.edu/server/api/core/bitstreams/54e90734-ceb5-4f4f-94f6-83e51cd2da73/content).
Theorem 1, verbatim:

> **Theorem 1. The algorithm A is finite.**
> **Proof.** The algorithm A terminates when L = 0. Each evaluation of step A3
> removes an element from L, and elements are added to L only in step A5. Thus,
> A is finite if the number of evaluations of step A5 is finite. Informally,
> each evaluation of step A5 reduces the "size" of the pool P_N at some node N.
> Since the size cannot be less than 0, the process must be finite. **Formally,
> step A5 is performed only when P_N ≠ P_N ∧ P_i.** But (P_N ∧ P_i) ∧ P_N =
> P_N ∧ P_i ⇒ P_N ∧ P_i ≤ P_N, and P_N ∧ P_i ≤ P_N ⇒ P_N ∧ P_i < P_N. Thus,
> the approximate pool P_N at node N can be reduced at most to 0 since
> P_N ≠ P_N ∧ P_i. Further, since the first approximation to P_N is 1 and
> **the lattice is finite**, it follows that step A5 can be performed only a
> finite number of times. Thus A is finite.

Read what the proof actually consumes. The chain-descent step is supplied
**entirely** by two properties of the *implementation*, not of the transfer
function:

1. The stored value is overwritten with **`P_N ∧ P_i`** -- a **meet with the
   OLD STORED VALUE**, never a raw overwrite with the newly computed value.
   This is what makes the new value provably `≤` the old.
2. The write happens **only when `P_N ≠ P_N ∧ P_i`** -- the **change guard**.
   This upgrades `≤` to strict `<`, which is what the finite-height argument
   consumes.

Monotonicity of `f` is **not used in the termination proof at all**. Kildall's
stated requirement on `f` is distributivity (p. 196,
`f(N, x ∧ y) = f(N,x) ∧ f(N,y)`), and it serves *correctness* (Theorem 2,
MOP = MFP), not termination.

**Stated precisely:** "monotone + finite height ⇒ terminates" is a theorem about
**Kleene iteration specifically** -- the discipline `x ← f(x)` from ⊥ applied to
the whole state vector. It does **not** cover an arbitrary implementation. An
implementation that stores `f(in)` directly, rather than `old ⊔ f(in)`, has no
chain-descent invariant, and can move a stored value **sideways** between two
incomparable lattice elements forever -- on a finite lattice, with a perfectly
monotone transfer function.

Independent confirmation from the Dragon Book's convergence argument, via
IIT-Delhi COL729 (from Ullman's Stanford `dragonbook` material,
https://iitd.github.io/col729/lec/dataflow_analysis_foundations.html), verbatim:

> "Given: ⋀ and monotone data flow framework [and] finite descending chain THEN
> converges!"
> "**It's value cannot go up (new value < old value) during algorithm.** Start
> with ⊤ (largest value)."

This is why NNH write the update as a join and Kildall writes it as a meet.
Neither writes a bare assignment.

### 1.4 The worklist algorithm and its exact re-enqueue rule

Nielson/Nielson/Hankin, *Principles of Program Analysis*, §2.4 (MFP solution),
verbatim from the authors' own slides ((c) F.Nielson & H.Riis Nielson &
C.Hankin, May 2005,
https://www.cmi.ac.in/~madhavan/courses/program-analysis-2014/slides/slides-23jan2014.pdf):

```
Step 1 Initialisation (of W and Analysis)
  W := nil;
  for all (l, l') in F do W := cons((l, l'),W);
  for all l in F or E do
    if l in E then Analysis[l] := iota else Analysis[l] := bottom_L;

Step 2 Iteration (updating W and Analysis)
  while W != nil do
     l := fst(head(W)); l' = snd(head(W)); W := tail(W);
     if f_l(Analysis[l]) NOT-SUBSUMED-BY Analysis[l'] then
       Analysis[l'] := Analysis[l'] JOIN f_l(Analysis[l]);
       for all l'' with (l', l'') in F do W := cons((l',l''),W);
```

Three details that matter:

1. **The guard is `⋢` (not-⊑), not `≠`.** It asks whether the new contribution
   adds anything not already present -- weaker and cheaper than inequality, and
   it correctly skips when the new value is *below* the stored one.
2. **The update is a join with the old value**, not an overwrite. This is the
   ascending twin of Kildall's `P ∧ P_i`, and it is what makes each cell's
   trajectory a chain.
3. **The re-enqueue rule:** when the guard fires, push every outgoing flow-edge
   pair `(l', l'')` -- the successors of the block whose value just changed.
   Nothing else is ever enqueued after initialization.

Both the store and the re-enqueue sit **inside the same guard**.

NNH on decidability, verbatim:

> The MFP solution is always computable (meaning that it is decidable)
> **because of the Ascending Chain Condition.**

### 1.5 Does a worklist change termination, or only cost?

**Only cost.** Three independent confirmations:

- **Kildall, Corollary 1**, verbatim:
  > The final pool P_N associated with each node N ∈ N upon termination of the
  > algorithm A is **uniquely determined, independent of the order of choice of
  > L' from L in step A3.**

  and:
  > Since the choice of L' from L in step A3 is arbitrary... **The number of
  > steps to the final solution is clearly affected by this choice.** No
  > selection method has been established, however, to maximize this convergence
  > rate.

- **Moller & Schwartzbach**: chaotic iteration "eventually terminates at a fixed
  point. It must be identical to the result of the naive algorithm since that is
  the least fixed point." And the worklist is "essentially a **specialization of
  chaotic iteration** that exploits the special structure of f."

- Kildall's complexity bound: step A5 executes at most `n · h(P')` times, where
  `h` is the maximum chain length. The bound depends on lattice height and node
  count -- not on the schedule.

**What preserves termination is the chain-descent invariant (join-with-old +
change guard), which round-robin and worklist both maintain. Not the worklist.**

For chalk this is the decisive fact: **no worklist is needed for correctness or
termination.** Re-scanning every node each round is a constant-factor cost, and
Kildall's own corollary says the answer is identical.

### 1.6 Direction: the textbooks disagree, and it is purely notational

- **NNH / Moller / Schwartzbach:** lattice oriented so analysis **ascends**.
  Init `⊥`, combine with `⊔`, ACC bounds the ascending chain, answer is the
  **least** fixed point.
- **Kildall / Dragon Book / Kam-Ullman:** lattice oriented so analysis
  **descends**. Init `⊤` (Kildall's `1`), combine with `∧`, finite **descending**
  chain bounds it, answer is the **Maximal** Fixed Point (MFP).

These are the same algorithm with the lattice drawn upside down. NNH explicitly
acknowledge the flip: theirs is "The MFP solution -- 'Maximum' (actually least)
Fixed Point". The invariant common to both: **the stored value moves
monotonically in exactly one direction and never reverses.**

### 1.7 Optimistic vs pessimistic -- and why it is NOT the same axis

Wegman & Zadeck, "Constant Propagation with Conditional Branches," TOPLAS 13(2),
April 1991, pp. 181-210
(https://www.cs.utexas.edu/~pingali/CS380C/2010/papers/p291-wegman.pdf).
Verbatim:

> **The algorithms start with the optimistic assumption of assigning top to the
> LevelCell of all variables at all nodes except the start node.** All LevelCells
> at the start node are assigned bottom. **The algorithms proceed by lowering (in
> the lattice theoretic sense) the LevelCells of the variables at each node, as
> more information is discovered. This proceeds until a fixed point is achieved.**
> The additional information is added by applying the meet rules.

Termination, verbatim:

> **Since each variable can only have its lattice value lowered twice, each node
> may be visited at most 2 × V times.**

"Lowered twice" is exactly the height of their three-level lattice
(top -> constant -> bottom). Same theorem, concrete instance.

Their change discipline, verbatim:

> **In that case all nodes following the examined node must be examined, and
> they are added to the worklist. If no values change, then no nodes are added
> to the worklist.**

**The terminology trap, stated plainly:** optimistic/pessimistic and
ascending/descending are **not synonyms**.

- **Optimistic / pessimistic** is about whether your STARTING ASSUMPTION is the
  precise-but-unproven one or the safe-but-imprecise one.
- **Ascending / descending** is about lattice ORIENTATION on the page.

An optimistic analysis's intermediate state is **unsound** -- you may not stop
early and use it. A pessimistic analysis's intermediate state is sound at every
step and can be halted anytime. That asymmetry, not the direction of the arrow,
is what distinguishes them.

Click's thesis states the safety asymmetry directly: "A bottom-up analysis can
be stopped prematurely; a top-down analysis cannot."

### 1.8 Is "compare and don't write if unchanged" a named technique?

**Essentially no. It has no distinct name, because it is not treated as an
optimization -- it is half the termination proof.**

In every primary source retrieved it appears as an unnamed conditional inside
the algorithm body:

- Kildall: step A4, unnamed (`[traverse?]` is a step label, not a technique).
- NNH: the `if ... ⋢ ...` in Step 2, unnamed.
- Moller/Schwartzbach: `if (y != xi)`, unnamed.
- Wegman & Zadeck: "If no values change, then no nodes are added" -- prose.

Nearest named concepts:

| Term | What it names | Is it this? |
|---|---|---|
| **Chaotic iteration** (Cousot) | Updating only some components per step, nondeterministic order; selection predicate is `xᵢ ≠ fᵢ(...)`. | **Closest match.** The change test is promoted to the component-selection predicate. |
| **Asynchronous iteration** (Cousot 1977) | Scheduling freedom; "ultimately stationary". | Related, but about scheduling, not the write guard. |
| **Stabilization / "ultimately stationary"** | The state of having converged. | Names the goal, not the technique. |
| **Widening** | A lossy accelerator for infinite-height lattices. | **No** -- widening trades precision for termination; the change guard trades nothing. |
| **"Monotone update"** | Not established terminology. No primary-source usage found. | No. |

---

## Part 2: per-system findings

Only **three** strategies exist in the wild for the recursive-call bootstrap,
and only one is a fixpoint.

| Strategy | Systems | Cost |
|---|---|---|
| **Unify** -- recursive occurrence gets one monomorphic tyvar | HM / ML / OCaml / Haskell | polymorphic recursion lost |
| **Declare** -- signature is an input, never an output | Java, C#, Rust, Go | annotation burden |
| **Iterate optimistically** -- start at ⊤, meet down to fixpoint | HotSpot C2, Graal | needs a lattice + termination argument |

TypeScript is a fourth case: it *detects* the cycle and gives up (`any`).

### 2.1 Hindley-Milner: unification makes bootstrap a non-problem

Milner 1978, "A Theory of Type Polymorphism in Programming"
(https://homepages.inf.ed.ac.uk/wadler/papers/papers-we-love/milner-type-polymorphism.pdf),
§3, well-typing clause (v), verbatim:

> `p ⊢ (fix x_σ . e_τ)_ρ` is wt iff `p . fix x_σ ⊢ e` is wt and **`ρ = σ = τ`**

Three equalities: the recursive occurrence's type, the body's type, and the whole
expression's type are **one type variable**. In prose (p. 353):

> "our rules demand that different occurrences of a formal parameter (f, for
> example), **or of an identifier (map) being recursively defined, shall have the
> same type.**"

Critically, `fix x` is grouped with `λx`, NOT with `let x`, in the
generic/non-generic split: only `let`-bound variables get generic instances.

Damas-Milner 1982 (https://steshaw.org/hm/milner-damas.pdf) omits recursion
entirely, deferring it to `fix : ∀α((α → α) → α)`. Generalization is a separate
LATER step: `Ā(τ) = ∀α₁,…,αₙ τ` where the αᵢ are "free in τ but not in A".

**Why bootstrap is a non-problem here.** A fresh unification variable is not a
*guess to be refined* -- it is a **hole with an identity**. Constraints from the
body flow into it by unification, which is monotone and confluent. There is no
lattice, no ascending chain, no iteration, and therefore **nothing to converge**.
This is a genuinely different mechanism from fixpoint iteration, not a variant
of it.

**Dependency analysis.** Haskell 2010 Report §4.5.1
(https://www.haskell.org/onlinereport/haskell2010/haskellch4.html), verbatim:

> "b1 depends on b2 if: b1 contains a free identifier that has no type signature
> and is bound by b2, or b1 depends on a binding that depends on b2." ...
> "A declaration group is a minimal set of mutually dependent bindings."

§4.5.2 gives the ordering: **first** "a type with no universal quantification is
inferred for each variable bound in the group", **then** generalization.
Monomorphic throughout the SCC; generalize once, after.

GHC implements exactly this in `compiler/GHC/Tc/Gen/Bind.hs`:

```haskell
sccs = stronglyConnCompFromEdgedVerticesUniq (mkEdges sig_fn binds)
-- Bring the monomorphic Ids into scope for the RHSs
```

The load-bearing detail: `mkEdges` draws an edge only when
`no_sig n = not (hasCompleteSig sig_fn n)` -- **a type signature DELETES EDGES
from the dependency graph**, shrinking the SCC. `Note [Polymorphic recursion]`
spells out the payoff: with mutually recursive `f` and `g` where only `g` has a
signature, GHC adds `g`'s signature to the environment, infers `f` alone, then
checks `g`.

**Why the monomorphic restriction is not laziness.** Henglein, *Type Inference
with Polymorphic Recursion*, TOPLAS 1993
(https://suif.stanford.edu/~brm/reading/p253-henglein.pdf), verbatim:

> "the type inference problem for the Milner-Mycroft Calculus is log-space
> equivalent to semiunification... In connection with the recently established
> undecidability of semiunification this implies that **typability in the
> Milner-Mycroft Calculus is undecidable.**"

Milner's restriction is the price of decidability.

### 2.2 Java and C#: declared signatures sidestep it entirely

**Java.** JLS SE21 §8.4.5
(https://docs.oracle.com/javase/specs/jls/se21/html/jls-8.html#jls-8.4.5):
`Result` is a mandatory constituent of `MethodHeader`. Zero return-type
inference.

JLS §14.4 on `var` -- compile-time error if:

> "**The initializer of the VariableDeclarator contains a reference to the
> variable.**"

Purely textual, not a cycle analysis. Example 14.4-1:
`var g = (g = 7); // Illegal: self reference in initializer`.

**C#.** ECMA-334 §13.6.2.2: `var v = v++; // Error, initializer cannot refer to
v itself` (CS0841). Caveat: C# states this in an *example*, not a normative
bullet; the normative force comes from the weaker "the expression shall have a
compile-time type, T". Java's citation is materially stronger.

C# local functions confirm the trade explicitly
(https://learn.microsoft.com/en-us/dotnet/csharp/programming-guide/classes-and-structs/local-functions):

> "**recursive algorithms are easier to create using local functions.** You can
> declare and define a local function that calls itself. **Lambda expressions
> must be declared and assigned a default value before they can be reassigned**
> to a body that references the same lambda expression."

Local functions: recursion allowed, return type mandatory. Lambdas: signature
inferred, no self-reference. **The trade is stated in the official docs.**

### 2.3 TypeScript: detect the cycle, fall back to `any`

Retrieved `src/compiler/checker.ts` v5.8.3 directly. The mechanism is a
**resolution stack**, not a fixpoint:

```typescript
function pushTypeResolution(target, propertyName): boolean {
    const resolutionCycleStartIndex = findResolutionCycleStartIndex(target, propertyName);
    if (resolutionCycleStartIndex >= 0) {
        const { length } = resolutionTargets;
        for (let i = resolutionCycleStartIndex; i < length; i++) {
            resolutionResults[i] = false;      // poisons EVERY frame from cycle start
        }
        return false;
    }
    ...
}
```

and in `getReturnTypeOfSignature`:

```typescript
if (!pushTypeResolution(signature, TypeSystemPropertyName.ResolvedReturnType)) {
    return errorType;                          // inner re-entrant hit
}
let type = getReturnTypeFromBody(...);
if (!popTypeResolution()) {                    // cycle detected
    if (typeNode) error(typeNode, Diagnostics.Return_type_annotation_circularly_references_itself);
    else if (noImplicitAny) error(name, Diagnostics._0_implicitly_has_return_type_any_because_...);
    type = anyType;                            // <-- the fallback
}
```

Two distinct outcomes: the *inner* re-entrant call returns `errorType`; the
*outer* call reports the diagnostic and yields `anyType`. Codes confirmed from
`diagnosticMessages.json`: **TS7023** (named), **TS7024** (anonymous),
**TS2577**, **TS2502**.

An annotation breaks the cycle -- the same lever as GHC's signatures and Rust's
mandatory signatures.

### 2.4 Rust: signatures mandatory, inference intraprocedural

Reference, "Inferred type"
(https://doc.rust-lang.org/reference/types/inferred.html), normative, one
sentence: **"The inferred type cannot be used in item signatures."**

The architectural statement, rustc-dev-guide HIR typeck
(https://rustc-dev-guide.rust-lang.org/hir-typeck/summary.html), verbatim:

> "each of these queries is concerned with *interprocedural* things -- for
> example, for a function definition, collection will figure out the type and
> signature of the function, **but it will not visit the *body* of the function
> in any way**"

Collection never reads bodies => a signature can never depend on a body => **no
recursion can create a signature-level cycle.** The acyclicity is **structural,
from phase ordering** -- not an occurs-check, not a fixpoint.

The exception proves the rule: `-> impl Trait` is the one place a body determines
a signature, and it immediately needs a dedicated error. E0720
(https://doc.rust-lang.org/error_codes/E0720.html): "An `impl Trait` type expands
to a recursive type" -- `T = [T, T]`, an occurs-check failure.

(Note: the commonly-cited `type-checking.html` URL is a 404; content moved to
`hir-typeck/summary.html`.)

### 2.5 Go: results declared; generic inference is call-site-local

Go spec (https://go.dev/ref/spec): `Signature = Parameters [ Result ]`. `Result`
is syntactically optional but its absence means **no results** -- a fixed
default, never inference.

Go 1.18+ inference is bounded to a use site: type arguments may be inferred "from
**the context within which the function is used**". Type arguments only, never
result types. `x := sum` is rejected outright rather than deferred.

### 2.6 HotSpot C2 and Graal: YES, optimistic init at TOP, meet downward

**This is the direct answer to the SoN question, and HotSpot's source states it
in a comment.**

`src/hotspot/share/opto/phaseX.cpp`, `PhaseCCP::analyze()`, verbatim:

```cpp
// In this analysis, all types are initially set to TOP. We iteratively call Value() on all
// nodes of the graph until we reach a fixed-point (i.e. no types change anymore).
void PhaseCCP::analyze() {
  // Initialize all types to TOP, optimistic analysis
  for (uint i = 0; i < C->unique(); i++)  { _types.map(i, Type::TOP); }
```

`cfgnode.cpp`, `PhiNode::Value` -- the meet starts from TOP and skips dead paths:

```cpp
const Type *t = Type::TOP;
for (uint i = 1; i < req(); ++i) {
  if (r->in(i) && phase->type(r->in(i)) == Type::CONTROL) {
    t = t->meet_speculative(phase->type(in(i)));
  }
}
```

Monotonicity is **asserted, not assumed** -- `PhaseCCP::verify_type` fatals with
`"Not monotonic"` if `tnew->meet(told) != tnew->remove_speculative()`.

**Both directions exist, split by PHASE**, via a virtual `saturate` hook
(`phaseX.hpp`):

```cpp
const Type* PhaseCCP::saturate(...)     { ... new_type->widen(old_type, limit_type) ... }  // optimistic
const Type* PhaseIterGVN::saturate(...) { return new_type->narrow(old_type); }             // pessimistic
```

with this comment, as clean a statement of the tradeoff as exists anywhere:

> "For pessimistic passes, the return type must monotonically narrow. For
> optimistic passes, the return type must monotonically widen. It is possible to
> get into a **'death march'** ... where it will take 2**31 or more steps to
> converge."
>
> "It's a pleasant thing to observe that the pessimistic pass will make short
> work of the optimistic pass's deadly loop, and vice versa."
>
> "In any case, only widen or narrow a few times before going to the correct
> flavor of top or bottom. **This call only needs to be made once as the data
> flows around any given cycle. We do it at Phis, and nowhere else.**"

Widening is applied **precisely at the cycle-cutting node**, bounded by
`enum WIDEN { WidenMin = 0, WidenMax = 3 }`.

**Click's thesis**, *Combining Analyses, Combining Optimizations* (1995),
retrieved (157pp; Rice's own copy is Cloudflare-blocked). Chapter 2, on exactly
the loop-phi bootstrap case:

> "If the same quad resides in a loop, it has the form `b := φ(a, b)`. **The
> bottom-up approach finds nothing. There are no elements ⟨b, c₀⟩; there is
> nothing to prime the cycle of dependencies.** However, the top-down approach
> finds a ⟨b, c₀⟩ pair for every matching ⟨a, c₀⟩ pair."

Definition 1: "We use the optimistic assumption when we find a set using the
top-down approach instead of the bottom-up approach."

**This is chalk's recursive-Call/Phi problem, named and solved, in the SoN
literature, by the author of Sea of Nodes.**

**Graal** does the same with stamps -- `ValuePhiNode.inferStamp()`:

```java
// Meet all the values feeding this Phi but don't use the stamp of this Phi since that's
// what's being computed.
Stamp valuesStamp = StampTool.meetOrNull(values(), this);
```

with `tryInferLoopPhiStamp` handling cases where phis are "initially built with
unrestricted object stamps". `CanonicalizerPhase.tryInferStamp` drives it to
fixpoint by re-queuing usages on change.

Click & Paleczny 1995 was retrievable
(https://www.oracle.com/technetwork/java/javase/tech/c2-ir95-150110.pdf; 403 via
WebFetch, fine via curl with a UA) but is about the IR, not the lattice. **The
thesis is the citation, not the paper.**

### 2.7 Widening is NOT needed at chalk's lattice height

Cousot & Cousot 1992, "Comparing the Galois connection and widening/narrowing
approaches"
(https://www.di.ens.fr/~cousot/COUSOTpapers/publications.www/CousotCousot-PLILP-92-LNCS-n631-p269--295-1992.pdf).
Widening axioms: `x ⊑ x∇y`, `y ⊑ x∇y`, and every chain
`y^{i+1} = y^i ∇ x^{i+1}` is not strictly increasing.

The direct answer, verbatim:

> "Widenings and narrowings are used when the domain L has **infinite or very
> long strictly ascending chains** or even when it is finite but very large."

and:

> "Observe that if L is a join-semi-lattice ... **satisfying the ascending chain
> condition, then ⊔ is a widening.**"

Moller & Schwartzbach, ch. 6 opening: "A central limitation ... is the
requirement that the lattices have finite height. In this chapter we describe a
technique called widening that **overcomes that limitation**." Exercise 6.10:
"**Show that ⊔ is a widening operator (albeit perhaps not a very useful one) if
L has finite height.**"

**For chalk's lattice (height ~6): widening is IRRELEVANT.** Plain Kleene
iteration terminates in <=5 raises per element. Adding ∇ either changes nothing
(∇ = ⊔) or actively destroys precision. The only carve-out -- "an acceleration
technique for analyses that have finite-height lattices but converge too slowly"
-- does not apply at height 6.

**Narrowing (Δ)** is the descending recovery pass, and exists ONLY to undo ∇'s
over-approximation: "Widening generally shoots above the target, but a subsequent
technique called narrowing may improve the result." **With no widening there is
nothing to recover.** If chalk wants downward refinement for a different reason
(a second pessimistic pass a la IterGVN), that is a distinct design and must not
be called narrowing.

### 2.8 Bidirectional typing is NOT bidirectional dataflow

**These are different things, and conflating them is a real error.**

| | Bidirectional **typing** | Forward/backward **dataflow** |
|---|---|---|
| Traverses | typing derivation over a **term/AST** | the **graph** |
| "Direction" means | whether the *type* is an **input or output** of a judgment (its **mode**) | whether values come from **ancestors or descendants** |
| Terminates by | **structural recursion**; syntax-directed | **fixpoint iteration** (lattice + ACC) |
| Visits per node | **once**, in one mode | **repeatedly**, until stable |
| Solves | decidability + annotation burden | approximating a property over all paths |

Dunfield & Krishnaswami, "Bidirectional Typing," ACM Computing Surveys 2021
(https://arxiv.org/abs/1908.05839) define it purely in terms of modes: "is each
of the meta-variables (Γ, e, A) an input, or an output? ... The status of each
meta-variable -- input or output -- is its **mode**." Termination comes from
syntax-directedness: "we can 'read off' an implementation from the rules."

Pierce & Turner, "Local Type Inference," TOPLAS 2000
(https://www.cis.upenn.edu/~bcpierce/papers/lti-toplas.pdf) stress locality:
"type information is propagated only between adjacent nodes in the syntax tree",
"**without long-distance constraints such as unification variables**." Their own
analogy is **attribute grammars**.

**The clinching structural point: bidirectional typing has no lattice, no ⊥, no
ascending chain, and no convergence test**, because the recursion is on a
well-founded syntax tree. Dataflow analysis is *defined by* its fixpoint. Neither
paper discusses fixpoints, lattices, or CFGs in a technical role at all -- that
absence is the evidence.

**The right term for what chalk does is "bidirectional data flow analysis."**
Jaiswal, Khedker & Chakraborty (https://arxiv.org/pdf/1802.00932) §4, verbatim:

> "In a bidirectional flow analysis, the data flow values at a node are
> influenced by both ancestors as well as descendants. Some examples ... partial
> redundancy elimination, **type inferencing**, and liveness based points-to
> analysis."

They name **type inferencing** as a bidirectional dataflow problem. Khedker/
Dhamdhere/Mycroft 2003 wrote a whole paper putting type inference in that
framework -- pointless if it were already what bidirectional typing meant.

If chalk's backward leg carries *requirements*, the precise term is
**demand-driven**, formalized as bidirectional dataflow:

> "demand-driven methods are inherently bidirectional with **demands being raised
> and propagated against the control flow** and the requisite information to
> satisfy the demands flowing along the control flow"

**On oscillation.** No paper is dedicated to it (see UNVERIFIED), because it is
not a property of bidirectionality -- it is the symptom of a **non-monotone
transfer function**. Jaiswal et al.: "Termination in a finite number of steps is
ensured by the fact that our flow functions are monotonic." Both legs monotone
over a finite lattice => terminates at the MFP by the same Kleene argument, and
oscillation is impossible. **A backward "requirement" that OVERWRITES rather than
MEETS is non-monotone -- that is the thing that oscillates.**

**Constraint-based inference** (Pottier & Remy, *The Essence of ML Type
Inference*, https://pauillac.inria.fr/~fpottier/publis/emlti-final.pdf) dodges the
question entirely by separating **generation from solving**: one accumulation
pass, then one solve. Nothing is iterated, so nothing can oscillate.

---

## Part 3: the six questions, answered directly

### Q1. What are the standard termination arguments, and does the update discipline matter?

**ACC / finite height + monotone transfer functions + Kleene iteration.**
Precisely stated in §1.1-1.2 above.

**And YES, the discipline matters -- decisively.** "Monotone + finite height =>
terminates" is a theorem about **Kleene iteration**, i.e. `x ← f(x)` from ⊥. It
says nothing about an implementation that stores `f(in)` directly.

The standard proof assumes the stored value at each point **only ever moves in
one direction along the lattice**. Kildall's Theorem 1 gets that assumption from
two implementation properties, neither of which is monotonicity of `f`:

1. store `old ∧ new` (meet/join **with the old stored value**), and
2. write **only when that differs from old**.

Chalk's hang was exactly this failure: the join was computed from inputs and
stored, and `$changed` was set unconditionally.

### Q2. Which direction does standard inference move, and is downward refinement a real technique?

**Both directions are standard; they are distinguished by SOUNDNESS OF THE
INTERMEDIATE STATE, not by the arrow's direction.**

- **Pessimistic**: start at the safe value, move toward precision. Intermediate
  state is sound; can be halted anytime.
- **Optimistic**: start at the precise-but-unproven value (⊤ in W&Z's
  orientation), lower monotonically as evidence arrives. Intermediate state is
  **unsound**; only the fixpoint may be used.

Ascending-vs-descending is just lattice orientation and is **not** the same axis.

**Downward refinement from `Scalar` toward `Int` is a real, named technique: it
is optimistic analysis** (Wegman & Zadeck 1991; Click's "top-down approach";
HotSpot's `PhaseCCP`). It terminates for the same reason ascending iteration
does -- a monotone one-directional walk on a finite-height lattice. The height
bound is the whole argument. W&Z's own phrasing: "each variable can only have
its lattice value lowered twice" on a 3-level lattice.

**The catch chalk must respect:** an optimistic analysis's intermediate values
are unsound. Nothing may consume a stamp until the fixpoint is reached. Chalk's
passes currently interleave stamping with consumption, which is safe under
pessimistic write-once and **is not automatically safe under optimistic
refinement.**

### Q3. What does a worklist buy?

**Cost only, never termination or the answer.** Kildall Corollary 1: the result
is "uniquely determined, independent of the order of choice". Moller &
Schwartzbach: the worklist is "essentially a specialization of chaotic
iteration."

Standard formulation: NNH §2.4 (quoted in full at §1.4). The re-enqueue rule is
**"on a change, enqueue the successors of the changed node"** -- and the store
and the enqueue live inside the **same** guard.

**Chalk needs no worklist.** Re-scanning every node each round is a constant
factor on a graph this size. What chalk needs is the guard, which it now mostly
has.

### Q4. How do real systems handle the recursive-call bootstrap?

Full table at Part 2 opening. Per system:

- **HM/ML/Haskell**: the recursive occurrence gets **one monomorphic unification
  variable**, unified through the body; generalization happens **after** the SCC
  is solved. Bootstrap is a non-problem because a tyvar is a hole with identity,
  not a guess to refine. Cost: polymorphic recursion is undecidable (Henglein).
- **Java / C# / Rust / Go**: **declared signatures sidestep it entirely.** Rust's
  is architectural -- collection "will not visit the body of the function in any
  way", so a signature-level cycle cannot exist. Where a body *does* determine a
  signature (`-> impl Trait`), a dedicated error appears (E0720).
- **TypeScript**: **detects the cycle with a resolution stack and falls back to
  `any`** (TS7023/TS7024). Not a fixpoint at all.
- **HotSpot C2 / Graal**: **optimistic iteration.** All types start at `Type::TOP`;
  `PhiNode::Value` meets its live inputs starting from TOP; iterate to fixpoint.
  **This is the direct answer to chalk's `fib` case.** Click's thesis states the
  bootstrap failure and its fix explicitly: "The bottom-up approach finds
  nothing... there is nothing to prime the cycle of dependencies. However, the
  top-down approach finds a ⟨b, c₀⟩ pair for every matching ⟨a, c₀⟩ pair."

**The internal doc's claim that a recursive callee "can never bootstrap" is true
only of the PESSIMISTIC write-once design.** It is not a property of the problem.
The optimistic formulation solves it, and does so inside a Sea-of-Nodes compiler.

### Q5. Do widening operators have any role at chalk's height?

**No. Irrelevant at height 6.** Cousot & Cousot: widening is for "infinite or
very long strictly ascending chains... or even when it is finite but very
large." And: "if L is a join-semi-lattice satisfying the ascending chain
condition, then ⊔ is a widening" -- i.e. chalk's plain join *already is* a
widening operator, trivially.

Adding a real ∇ would only lose precision. **Narrowing is equally irrelevant**:
it exists solely to recover precision that widening threw away.

The one place widening-like machinery appears in a finite-lattice SoN compiler is
HotSpot's `WidenMax = 3` bound on integer RANGES -- which is an *infinite*
sublattice (range endpoints), not the finite type spine. Chalk has no such
sublattice today.

### Q6. What stops a fixpoint that re-derives the same value forever?

**"Compare and don't write if unchanged" -- and yes, that is the standard
mechanism.** It is Kildall's step A4, NNH's `⋢` guard, W&Z's "If no values
change, then no nodes are added to the worklist", and Moller & Schwartzbach's
`if (y != xi)`.

**Is it a named technique? Essentially no**, and the reason is important: it is
not regarded as an optimization at all -- it is **half of the termination proof**.
The closest named concept is Cousot's **chaotic iteration**, where the change
test is promoted to the component-selection predicate.

So: **"no write without a move" is the standard fix, and it is more fundamental
than the write-once latch it replaced.**

**But chalk has implemented only ONE of Kildall's two halves.** See Part 4.

### Q7. Two-direction inference

Answered at §2.8. Summary:

- **Bidirectional type checking (Pierce & Turner; Dunfield & Krishnaswami) is NOT
  what chalk is doing.** It is a mode discipline on a syntax-directed judgment
  over a TREE; it terminates by structural recursion, has no lattice, and visits
  each node once.
- **What chalk is doing is bidirectional data flow analysis** -- and Jaiswal/
  Khedker/Chakraborty name **type inferencing** as a canonical instance of it.
  If the backward leg propagates requirements, the term is **demand-driven**.
- **What keeps the two legs from fighting: monotonicity of BOTH.** Both legs
  monotone over a finite lattice => terminates at the MFP by the same Kleene
  argument. Oscillation is not a hazard of bidirectionality; it is the symptom of
  a **non-monotone leg**, and the specific non-monotone move is a backward
  requirement that **overwrites instead of meeting**.
- **C2's answer to the same problem is to make the pessimistic direction a
  SEPARATE PHASE** (IterGVN narrowing) rather than a second leg interleaved into
  the optimistic one -- with the observation that "the pessimistic pass will make
  short work of the optimistic pass's deadly loop, and vice versa."

---

## Part 4: what this implies for chalk

### 4.1 Measured state of the code

All line numbers `lib/Chalk/IR/Analysis.pm` at commit `6db5dcdc`.

**The lattice satisfies every theoretical precondition.**
`lib/Chalk/Grammar/Perl/TypeLibrary.pm`: 26 members, explicit `%PARENT` chains
terminating at `Unknown`, `None` as bottom. Scalar spine
`Int -> Num -> Str -> Scalar -> List -> Unknown`, height ~6. `join_types` is a
genuine LUB (nearest common ancestor, "walking nearest-first makes it the LEAST
upper bound rather than merely an upper bound"). **ACC holds. Finite height
holds. No widening is needed.**

**The forward fixpoint (`_propagate_computed_reprs`, :1254) has 6 `$changed = 1`
sites; 4 are now guarded by `next if defined $prev && $prev eq ...`.**

**One is NOT guarded** -- the static-miss `Undef` stamp at :1303:

```perl
$node->set_stamp('Undef');
$changed = 1;
next;
```

This site terminates today **only because `_is_narrowed('Undef')` is true**
(verified by direct call). If `Undef` ever becomes refinable, this site diverges
immediately. **The write-once latch is still load-bearing for exactly one write.**

**`_seed_direct_call_arg_reprs` (:657) already implements Kildall's discipline
COMPLETELY, and is the only pass that does.** Its own comment states the
argument correctly:

> the existing stamp is folded INTO the join, so a stamp only ever moves UP the
> lattice, and the lattice is finite with `Unknown` at the top.

and the code does both halves:

```perl
my $joined = _join_repr( grep { defined } $existing, $slot->{reprs}->@* );   # meet/join with OLD
next if defined $existing && $existing eq $joined;                          # change guard
$read->set_representation($joined);
```

**This is `P_N ∧ P_i` plus `P_N ≠ P_N ∧ P_i` -- Kildall's Theorem 1, in chalk,
already written.**

**The main loop does NOT fold the old value in.** It computes `_join_repr` over
INPUTS only and stores the result. That is the missing half, and it is precisely
why loosening `_is_narrowed` hung: without `old ⊔ new`, a stored value can move
**sideways**, and the change guard alone cannot prevent an infinite walk between
incomparable elements. It only terminates today because the reachable moves
happen to be upward.

**`BackwardInference` (`lib/Chalk/IR/Transform/BackwardInference.pm`) has NO
PRODUCTION CALLER** -- verified by repo-wide grep; only `t/bootstrap/ir/
backward-inference.t` references it. It is also the **only** consumer of
`meet_types`. And it terminates by a **hard `$ROUNDS = 10` cap**, not by a
convergence argument.

So chalk currently has **three different termination strategies** in one
pipeline: a write-once latch (main loop), a proper Kildall fixpoint (call args),
and a bounded round cap (backward, unwired).

**Node setters enforce nothing.** `Chalk::IR::Node::set_stamp` /
`set_representation` are bare assignments. Monotonicity is maintained only by
convention at each call site -- there is no structural guarantee.

### 4.2 Recommendations, in dependency order

**R1. Fold the old value into the join in the main loop.** One-line-per-site
change: `_join_repr($node->representation, @computed)` instead of
`_join_repr(@computed)`. This supplies Kildall's missing half, makes every
stored value's trajectory a provable chain, and **removes the last dependence on
`_is_narrowed` as a termination device**. Without it, the current green is
luck-of-the-reachable-moves, not a proof.

**R2. Guard the static-miss `Undef` write at :1303.** It is the one unguarded
write, and it is currently protected only by `Undef` being latched.

**R3. Enforce monotonicity in the setter, not by convention.** Make
`set_representation` assert `is_subtype(old, new)` (or the optimistic dual)
under a debug flag. HotSpot does exactly this -- `PhaseCCP::verify_type` fatals
with "Not monotonic". Chalk's memory notes record a shipped miscompile
(`backward_inference_fills_holes_only`, gate 215->199) that is exactly a
non-monotone stamp; a setter assertion catches that class structurally.

**R4. The write-once guard is a LEGITIMATE DESIGN, but it is the PESSIMISTIC
one, and it is the reason recursion cannot bootstrap.** It is not a mistake --
it is a sound, standard, halt-anytime analysis whose intermediate state is always
usable. That property is load-bearing for chalk today, because passes interleave
stamping with consumption. But it structurally forbids optimistic iteration, and
therefore structurally forbids the recursive-Call fixpoint.

**R5. For the recursive-call bootstrap, adopt the optimistic formulation, as a
SEPARATE PHASE.** This is C2's architecture, stated in its own source: optimistic
`PhaseCCP` and pessimistic `PhaseIterGVN` are different phases with different
`saturate` hooks, and "the pessimistic pass will make short work of the
optimistic pass's deadly loop, and vice versa." Concretely for chalk:

- Recursive callee Returns / loop Phis start at the **precise** end (`None`, the
  bottom, as the join identity -- chalk's `join_types` already returns the other
  operand for `None`, so a `None`-initialized Phi joins to exactly its known
  arms). `fib`'s base case `Int` then flows without the recursive edge
  contributing anything, which is exactly Click's "top-down approach finds a
  ⟨b, c₀⟩ pair for every matching ⟨a, c₀⟩ pair."
- **Nothing may consume these stamps until the phase's fixpoint is reached.** This
  is the non-negotiable cost of optimism, and it is why it must be a separate
  phase rather than a loosened guard inside the existing interleaved passes.
- Termination is the height bound: <=6 moves per node. No widening.

**R6. When `BackwardInference` is wired up, replace the `$ROUNDS = 10` cap with a
monotonicity argument.** A round cap is not a termination proof -- it is a
silent-truncation hazard: at round 10 the analysis stops with no signal that it
had not converged. Since the backward leg uses `meet_types` and both legs are
monotone over a finite lattice, the standard Kleene argument applies directly and
the cap can be dropped (or kept purely as an assertion that fires loudly).

**R7. Stop calling it bidirectional type checking.** The correct term is
**bidirectional data flow analysis**, or **demand-driven** for the
requirement-propagating leg. The distinction is load-bearing: bidirectional
typing's soundness rests on syntax-directedness over a TREE, and **that argument
does not transfer to a graph**. Chalk's obligations are the dataflow ones --
monotone transfer functions on a lattice with ACC.

**R8. Do not build a worklist.** Kildall's Corollary 1 says it changes nothing but
speed, and chalk's graphs are small. Every-node-rescan is fine.

---

## UNVERIFIED / COULD NOT CONFIRM

- **Dragon Book (Aho/Lam/Sethi/Ullman, 2nd ed.) §9.3 primary text.** Eight
  mirrors failed (404 x4, 503, empty HTML, two curl timeouts at 550s). The
  literal "Algorithm 9.25" numbering and the book's exact wording are
  **unconfirmed**. All Dragon Book claims here rest on two independent
  Ullman-derived course sources (IIT-Kanpur CS738; IIT-Delhi COL729, from
  Ullman's Stanford `dragonbook` material) that agree with each other.
- **Cousot & Cousot 1977 (POPL) verbatim text.** The ENS-hosted PDF is a scan
  with no text layer. The 1992 paper's restatement of both ∇ and Δ definitions
  (citing [CC76, CC77a]) was used as the authoritative substitute.
- **Kam & Ullman 1977, "Monotone data flow analysis frameworks."** Abstract only;
  full text not retrieved.
- **Cousot & Cousot, "Efficient chaotic iteration strategies with widenings."**
  Abstract/metadata only. The chaotic-iteration claims here rest on Moller &
  Schwartzbach's presentation.
- **Khedker & Dhamdhere 1999** (bitmap-font PostScript, ACM paywalled) and
  **Khedker/Dhamdhere/Mycroft 2003** (Elsevier paywalled). The bidirectional-
  dataflow claims rest on Jaiswal/Khedker/Chakraborty (arXiv:1802.00932), which
  is retrievable and cites them.
- **Official C# LDM rationale** for local functions having mandatory return types
  *because of* recursion. The Microsoft docs state the trade; the "because" in
  csharplang#943 is from a community commenter, not a design note.
- **A dedicated source on OSCILLATION in bidirectional analyses.** None found.
  The claim that oscillation is a symptom of non-monotonicity rather than of
  bidirectionality is an inference from Jaiswal et al.'s monotonicity-based
  termination argument, not a direct quotation.
- **Click & Paleczny 1995** was retrieved but contains nothing on the type
  lattice; the optimistic-analysis material is in Click's 1995 thesis, retrieved
  separately from a non-canonical mirror (Rice's copy is Cloudflare-blocked).
  The thesis text quoted here was not cross-checked against a second copy.
- **The claim that chalk's main-loop join "only terminates today because the
  reachable moves happen to be upward"** is reasoning from the code's structure
  plus the observed 457,642-iteration hang, not from an exhaustive proof over
  chalk's node types. It is a hazard, measured once; it has not been shown to be
  reachable again under the current guard set.
