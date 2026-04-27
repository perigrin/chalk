# Formal Definition of Perl's Latent Dynamic Type System

## Overview

This document presents a formal model of Perl's latent type system, derived
from operational semantics and based on two key principles:

1. **Type membership** is defined by syntactic preservation through coercion
   and semantic fulfillment of operational contracts
2. **Subtyping relationships** are defined by set containment and operation totality

We present the first formal characterization of Perl's type system, using a
novel combination of syntactic preservation tests and semantic contracts to
handle pervasive coercion in a dynamically-typed language. It provides a
rigorous foundation for understanding why Perl behaves the way it does with
types, and enables building better static analysis tools, type checkers, and
optimizers for Perl code.

**Status of this work:** This formalization is a work in progress. While we believe the core definitions are sound and the proofs sketched here are valid, this work has not yet been mechanized in a proof assistant. The circular definitions of base types (Scalar and List) are conjectured to have a unique fixed-point solution, but formal proof of existence, uniqueness, and correspondence to Perl's actual semantics remains future work. We present this formalism as a foundation for discussion and tool development, acknowledging that full mechanization will strengthen or potentially revise some claims.

**Perl Version:** This formalization applies to Perl 5.36+. While the core type system (Scalar, Str, Num, Int, Ref) applies to all Perl 5 versions, specific features discussed require:
- Perl 5.36+: Primitive boolean values (`true`, `false`, `is_bool()`)
- Perl 5.38+: Native class objects (`feature 'class'`)
- Perl 5.40+: Stabilized class feature

The operational semantics and coercion rules reflect Perl 5.38 behavior.

**For practitioners:** A companion document, 1-perl-types-practical.md, presents these concepts in more accessible terms with practical examples and comparisons to existing Perl type systems like Moose and Types::Tiny.

**Reading guide:**
- Want the intuition? Read sections on Motivation, The Type Lattice, and Examples
- Building tools? Focus on Type Membership Definition and the concrete examples
- Verifying the theory? Read the Formal Framework and proof sections

## Motivation: Why Formalize Perl's Types?

Perl 5's latent type system has a strong reputation for inconsistency:
operations trigger implicit coercions depending on context, which appear to
affect type behavior at runtime. Despite decades of practical use, this system
has never been formalized at the language level. While Perl doesn't have
explicit type declarations, experienced Perl programmers develop strong
intuitions about which values "are" numbers versus strings. Consider these
examples:

```perl
my $x = "42";
my $y = $x + 1;     # $y is 43 - "42" behaves like a number
my $z = $x . "!";   # $z is "42!" - "42" behaves like a string
```

The value `"42"` is simultaneously usable as both a number and a string. But
some values don't work everywhere:

```perl
my $a = "hello";
my $b = $a + 1;     # $b is 1 - "hello" becomes 0, likely a bug
```

**The question:** What makes `"42"` a valid number but `"hello"` not?

**Traditional answer:** "Perl just coerces everything, so everything is both a
number and a string." This is incomplete - coercion happens, but not all
coercions make semantic sense.

**Claim:** A value belongs to a type if:
1. It survives coercion without losing information (syntactic preservation)
2. It behaves correctly under the type's operations (semantic fulfillment)

For `"42"`:
- Converts to number 42, then back to "42" ✓ (no information lost)
- Arithmetic works correctly: `42 + 1 = 43`, `42 == 42` ✓ (semantically meaningful)

For `"hello"`:
- Converts to number 0, then to "0" ✗ (lost the original value)
- Arithmetic is meaningless: `"hello" == "goodbye"` returns true (both become 0)

The formalization makes the intuitions of Perl programmers precise and checkable.

## Foundation

### Value Space

Let **V** denote the set of all possible Perl scalar values. This is the
universal space in which all values exist.

### Observational Equivalence

We use **≡** to denote observational equivalence. Two values are
observationally equivalent if they behave identically under all operations that
distinguish values in their domain, regardless of their internal representation.
For example, the integer 42 and the string "42" are observationally equivalent
even though they may be stored differently - they produce identical results
under all interpretation coercions.

The formal definition of observational equivalence is given in the Formal
Framework section below.

## Formal Framework

Let's provide precise mathematical definitions for the intuitions described
above. If you're building tools or verifying claims, you'll need this. If you
just want to understand Perl's type behavior, you can skim this and focus on
The Type Lattice and Examples sections.

**The quick gist:** We model Perl with a minimal calculus (a simplified formal
language), define how coercions work, and then use those coercions to determine
type membership. This is not a formal description of the entire language, but it
captures the essence of what we're claiming Perl's type system does.

### Core Calculus Syntax

Think of this as "Perl, but simplified to just the parts
relevant for types":

**Values and Expressions:**

```
Values v ::= n | s | undef | true | false | (v₁,...,vₙ)
          | ref(v) | aref(v₁,...,vₙ) | href(k₁=>v₁,...,kₙ=>vₙ)

Expressions e ::= v | $x | @x | %x | e₁ op e₂
               | my $x = e in e' | my @x = e in e'
               | \e | $$r | @$r | %$r
               | $x[e] | $x{e} | (e₁,...,eₙ) | f(e₁,...,eₙ)
```

**Sigils and Context:** Every Perl expression is evaluated in an evaluation
context (Scalar, List, or Void), and scalar values may be interpreted in value
contexts (Numeric, String, Boolean). During assignment, sigils ($, @, %)
determine evaluation context. The declaration `my $x = e` evaluates e in scalar
context, while `my @x = e` evaluates e in list context.

Full syntax and builtin signatures are detailed in Appendix A.

### Coercion Judgments

Coercions are the foundation (Layer 0) of the type system. A coercion is an
automatic transformation that reinterprets a value in a different type domain,
potentially changing its representation while preserving (or approximating) its
semantic content. Coercions happen automatically when values are used in
contexts that require a particular container type (Scalar, List) or a
particular value interpretation (Numeric, String, Boolean).

For example, the boolean value `true` coerces to 1 in numeric context and the
string `"1"` in string context.

We write `v ⇓^T u` to mean "value v coerces to type T yielding value u".
Selected rules:

**Numeric Coercion:**
```
n ⇓^Num n                          (literals are themselves)
"42" ⇓^Num 42                      (valid numeric strings parse)
"hello" ⇓^Num 0                    (invalid strings become 0)
ref(v) ⇓^Num addr                  (references become addresses)
```

**String Coercion:**
```
s ⇓^Str s                          (strings are themselves)
42 ⇓^Str "42"                      (numbers stringify)
ref(v) ⇓^Str "TYPE(addr)"          (references show type+address)
```

Complete coercion rules are in Appendix B.

### Observational Equivalence (Formal Definition)

**When are two values "the same"?** We need a formal way to say when two values are equivalent for the purposes of type membership. Two values are observationally equivalent (written v₁ ≡ v₂) if they behave identically under all the coercions that matter.

**In Perl terms:** The integer 42 and the string "42" are observationally equivalent because:
- Both stringify to "42"
- Both numify to 42
- Both are truthy in boolean context

Even though they might be stored differently internally, they're indistinguishable through Perl operations.

**Why this matters:** We use observational equivalence to test whether coercions preserve information, and whether values belong to types based on how the operators for that type behave. If v coerces to T and back, and the result is observationally equivalent to the original, then no information was lost, and if it can perform all of the T-specific operations then it's functionally a member of T.

```
[Observational-Equivalence-Scalar]
v₁ ⇓^Str s₁    v₂ ⇓^Str s₂    s₁ eq s₂
v₁ ⇓^Num n₁    v₂ ⇓^Num n₂    n₁ == n₂
v₁ ⇓^Bool b₁   v₂ ⇓^Bool b₂   b₁ == b₂
-----------------------------------------------
v₁ ≡ v₂

[Observational-Equivalence-Ref]
v₁ = ref(u₁)    v₂ = ref(u₂)    u₁ ≡ u₂
-----------------------------------------
v₁ ≡ v₂

[Observational-Equivalence-List]
v₁ = (w₁,...,wₙ)    v₂ = (w'₁,...,w'ₙ)
∀i ∈ 1..n: wᵢ ≡ w'ᵢ
-------------------------------------------
v₁ ≡ v₂
```

Two values are observationally equivalent if they produce identical results under all interpretation coercions. For scalars, we test using primitive equality operations (==, eq) on coercion results. For references, we require the referents to be observationally equivalent (reference identity is captured through string coercion showing identical addresses). For lists, all corresponding elements must be observationally equivalent.

### Evaluation and Operations

**How do expressions become values?** When you write `$x + 1`, Perl needs to figure out what value that produces. Evaluation rules specify exactly how this happens - they define which operations require which type interpretations, and how results are computed. Different operations impose different type requirements: addition requires numeric values, concatenation requires strings, and so on.

Evaluation rules define how expressions reduce in different contexts:

```
Γ ⊢ e ⇓^Scalar v          (scalar context produces single value)
Γ ⊢ e ⇓^List (v₁,...,vₙ)  (list context produces sequence)
```

Example - numeric addition imposes numeric interpretation:
```
[Plus]
Γ ⊢ e₁ ⇓^Scalar v₁    v₁ ⇓^Num n₁
Γ ⊢ e₂ ⇓^Scalar v₂    v₂ ⇓^Num n₂
n₁ + n₂ = n₃
---------------------------------------
Γ ⊢ e₁ + e₂ ⇓^Scalar n₃
```

From evaluation rules, we mechanically derive Operations(T). Let OpRules be the set of all operational evaluation rules in the semantics:

```
[Operations-Derivation]
Operations(T) = {op | ∃rule ∈ OpRules.
                      ∃Γ,v,u,e₁,...,eₙ. rule contains premise (v ⇓^T u)}
```

An operation op belongs to Operations(T) if and only if its evaluation rule requires coercing some value to type T. Thus `+ ∈ Operations(Num)` because [Plus] requires `v ⇓^Num`, and `. ∈ Operations(Str)` because string concatenation requires `v ⇓^Str`.

Complete evaluation semantics in Appendix C.

## Type Membership: Syntactic Component

A value belongs to a type if you can convert it to that type without losing information. An easy test for this is to convert it to the type and back and see if it's the same as it was before the coercions.

**In Perl terms:**
```perl
# Does "42" belong to Num?
my $original = "42";
my $as_num = 0 + $original;    # Force numeric: 42
my $back = "$as_num";           # Back to string: "42"
# $back eq $original ? YES - "42" ∈ Num
```

**Why this works:** If converting to Num and back changes the value, then information was lost during the conversion to Num, so the original value didn't really "fit" the type.

We call this "syntactic preservation" because we're testing whether the syntactic structure (the information content) is preserved through coercion.

**Note on type well-formedness:** For a type T to be well-defined in this formalism, there must exist some reference type S distinct from T with a coercion from T to S. This ensures types participate meaningfully in Perl's coercion system rather than being isolated. The constraint S ≢ T prevents vacuous membership tests (comparing a type to itself). These well-formedness conditions are implicit in the definitions below.

For a value v and type T with reference type S, the syntactic preservation property tests whether the value survives interpretation through T without losing essential structural content.

**Informal definition:**
```
syntactic_preservation(v, T, S) iff C(v) ≡ id_S(v)
```

where:
- C: T→S is the coercion that interprets v through T's semantic domain and then converts to S (the "detour")
- id_S(v) is the direct interpretation of v as type S, without any detour through T (the "direct path")
- The notation id_S means "identity coercion to S" - just convert v directly to S without going through T first

**The detour test:** Does taking a detour through type T change where you end up when heading to reference type S? If the detour makes no difference, then the value was innately compatible with T's interpretation. If the detour changes the result, then information was lost and the value does not belong to T.

**Choosing the reference type S:** Different types can use different reference types for testing. The key is picking a type that preserves enough information to tell if the round-trip worked.

For example:
- Testing if something is a **Num**? Use S = Str (strings preserve the digits)
- Testing if something is an **ArrayRef**? Could use S = List (dereference and see if contents match) or S = Ref (check the reference itself)

The formalism is flexible about which reference type you pick for each test - it just requires that at least one suitable reference type exists for each type being defined.

### Formalization

```
[Syntactic-Preservation]
v ⇓^T u    u ⇓^S w₁
v ⇓^S w₂
w₁ ≡ w₂
S ≠ T
-------------------------
SyntacticPreservation(v, T, S)
```

The detour through T (v → u → w₁) produces the same result as the direct path (v → w₂).

## Type Membership: Semantic Component

**The behavior test:** Even if a value survives the round-trip, it still needs to behave correctly when used with the type's operations.

**In Perl terms:**
```perl
# "hello" and "goodbye" both become 0 when numified
my $x = "hello";
my $y = "goodbye";
say $x == $y;  # prints 1 (true) - but this is nonsense!
```

The problem: `"hello"` and `"goodbye"` are different values, but numeric equality says they're the same. The operation executes, but the result is semantically meaningless.

**Why we need this:** Syntactic preservation alone isn't enough. Consider "NaN" (the string containing the letters N, a, N):
- Round-trip test: "NaN" → NaN (IEEE float) → "NaN" ✓ (survives!)
- But: `NaN == NaN` is false in IEEE 754
- And: `NaN - NaN` produces NaN (not 0 as expected)

"NaN" passes the structure test but fails the behavior test, so it's not a valid Num. A type is defined not just by what values look like, but by what you can meaningfully *do* with them.

**Informal definition:**

For a value v and type T, semantic fulfillment is true if and only if for every operation in Operations(T), the contract for that operation is satisfied by the value.

```
semantic_fulfillment(v, T) iff ∀op ∈ Operations(T): Contract_op(v)
```

where:
- Operations(T) is the set of all operations for which clients of type T have semantic expectations
- Contract_op(v) is a predicate asserting that applying operation op to value v satisfies the operation's semantic contract

A semantic contract specifies both preconditions and postconditions that define meaningful behavior for an operation. The operation must execute without error (satisfying preconditions), but more importantly, it must produce results that are semantically meaningful according to the operation's intended purpose (satisfying postconditions).

**Example - numeric equality contract:** The operation `==` should correctly distinguish between distinct values in a numerical context. When "hello" == "goodbye" returns true (both become 0), this violates the contract even though the operation executed successfully.

Semantic contracts capture what operations are *intended to do*, not merely what they *mechanically compute*. This distinction is essential for characterizing types in a language like Perl where operations are pervasive and promiscuous, evaluating nearly any input through aggressive coercion, but not all evaluations are semantically meaningful.

### Formalization

Operation contracts are defined relative to a reference type S:

```
[Contract-Operation]
∀v₁, v₂: (SyntacticPreservation(v₁, T, S) ∧ SyntacticPreservation(v₂, T, S)) ⟹
    ((v₁ ⇓^S u₁) ∧ (v₂ ⇓^S u₂) ∧ (u₁ op_S u₂ ⇓^S r_S) ∧
     (v₁ ⇓^T w₁) ∧ (v₂ ⇓^T w₂) ∧ (w₁ op_T w₂ ⇓^T r_T) ∧ (r_T ⇓^S r_S')
     ⟹ (r_S ≡ r_S'))
---------------------------------
Contract_op(T, S)
```

For values passing syntactic preservation, operating in source domain S should match operating in target domain T.

```
[Semantic-Fulfillment]
v ⇓^T u
∀op ∈ Operations(T): ∃S: Contract_op(T, S)
-------------------------------------------
SemanticFulfillment(v, T)
```

Contracts quantify over values passing syntactic preservation, which depends only on coercions (Layer 0), not on type membership. This avoids circular dependency. By defining operation contracts in terms of coercion behavior rather than type membership itself, we can use these contracts to determine membership without requiring that we already know which values belong to the type.

## Complete Type Membership Definition

We're finally ready to define type membership - that is, what we actually mean when we say a value v is of type T.

A value v belongs to type T if and only if both the syntactic preservation and semantic fulfillment conditions are satisfied:

Informally:
```
v ∈ T iff (∃S: S ≢ T ∧ C(v) ≡ id_S(v) where C: T→S)
        ∧ (∀op ∈ Operations(T): Contract_op(v))
```

A value v is a member of type T if and only if there exists some reference type S (distinct from T) such that interpreting v through T and then converting to S produces the same result as converting v directly to S, and v satisfies the semantic contracts of all operations defined for type T.

This definition has two essential components working together. The syntactic component identifies which values have representations that can survive interpretation through the type's semantic domain without loss of essential information. The semantic component identifies which values can meaningfully participate in the operations that the type supports, satisfying the contracts that clients of the type expect.

Both components are necessary. A value that passes syntactic preservation but fails semantic fulfillment has the right structure but cannot perform the type's intended behaviors. A value that fails syntactic preservation lacks even the structural prerequisites for membership, making its behavioral properties moot.

### Formalization

```
[Type-Membership]
∃S: SyntacticPreservation(v, T, S)
SemanticFulfillment(v, T)
-------------------------------------------
v ∈ T
```

The reference type S used for syntactic preservation may differ from reference types used in operation contracts. This flexibility allows characterizing each type relative to the most appropriate reference types.

## Subtyping Relationship

Type A is a subtype of type B, written A <: B, if and only if every value in A is also in B and every operation defined on B behaves correctly on values from A:

Informally:
```
A <: B iff (A ⊆ B) ∧ (∀op ∈ Operations(B): ∀v ∈ A: Contract_op(v))
```

The first condition (A ⊆ B) establishes set containment. Every value that belongs to A must also belong to B, which follows from both types using the same or compatible membership tests with A having strictly more demanding requirements than B.

The second condition ensures operational substitutability. Every operation that clients of type B expect to work must behave correctly (satisfy its semantic contract) when applied to values from A. This captures the essence of the Liskov Substitution Principle: values of a subtype can be used wherever values of the supertype are expected without breaking the program's correctness guarantees.

Together, these conditions guarantee that subtyping represents true behavioral substitutability, not merely set-theoretic containment. Type A is a safe substitute for type B both structurally (having the right kind of values) and behaviorally (supporting the right operations with correct semantics).

### Formalization

```
[Subtyping]
∀v ∈ V: (v ∈ A ⟹ v ∈ B)
∀v ∈ A: ∀op ∈ Operations(B): ∃S: Contract_op(B, S) holds for v
---------------------------------------------------------------
A <: B
```

Basic properties:

```
[Subtyping-Reflexive]    [Subtyping-Transitive]
---------                A <: B    B <: C
T <: T                   ----------------
                         A <: C
```

## The Type Lattice

A lattice is a mathematical structure from category theory that describes how elements are ordered and related to each other. In our case, it's a formal way to describe how Perl's types are organized - which types contain which values, and how types relate to each other through subtyping. The term "lattice" comes from the structure having a top element (containing all values), a bottom element (containing no values), and well-defined ways that types can be combined and related. For our purposes, you can think of it as an organized hierarchy showing how Perl's types fit together.

### Top Types (Pragma Types)

Top types are the most general types, the type that contains every value we can operate on. This is useful because it represents the most general case when we know nothing about a value (Unknown) or we explicitly want to allow any value (Any). They serve as the foundation from which more specific types can be derived through subtyping.

```
Unknown := V
Any := V
```

Both **Unknown** and **Any** contain all possible values, but serve different purposes in type checking tooling:

- **Unknown**: Default state for unanalyzed expressions; signals a type checker to attempt inference
- **Any**: Explicit polymorphic type; signals a type checker to accept without inference

These are **pragma types** with identical value sets but different tooling semantics. They represent the universal type at the top of the type hierarchy.

### Scalar Types

Scalar represents values that maintain identity as singular, atomic values through scalar operations. This is a concrete type, not merely an abstract context category. Scalar contains values that belong neither to Str nor to Num - including Boolean (true/false), Undef (undef), Ref (references), and DualVars (values with independent string and numeric interpretations) - proving Scalar's status as a distinct type with its own membership criteria. See Example 4 for more details about DualVars.

```

Scalar := {v ∈ V | v can be stored in and retrieved from a scalar variable
                    while maintaining its essential identity}

Boolean := { true, false }

Str := {v ∈ Scalar | ∃S: (S ≢ Str) ∧ C(v) ≡ id_S(v) where C: Str→S}
    ∧ {v | v satisfies string operation contracts}

Num := {v ∈ Scalar | ∃S: (S ≢ Num) ∧ C(v) ≡ id_S(v) where C: Num→S}
     ∧ {v | v satisfies numeric operation contracts}
     = {v | v has lossless numeric interpretation and supports numeric operations}
     = {v | v ⇓^Num n ∧ n ∉ {NaN, Inf, -Inf} ∧ numeric_contracts(v)}
     = {'42', 42, '3.14', 3.14, ...}
     ⊄ {'hello', '0 but true', 'NaN', 'Inf', ...}

where numeric_contracts(v) requires operations preserve algebraic properties:
- Reflexivity: v == v
- Subtraction identity: v - v = 0
- Addition commutativity: v₁ + v₂ = v₂ + v₁
- Finite arithmetic closure

Int := {v ∈ Num | ∃S: (S ≢ Int) ∧ C(v) ≡ id_S(v) where C: Int→S}
    ∧ {v | v satisfies integer operation contracts}
    = {v | v has lossless integer interpretation}
    = {'42', 42, ...}
    ⊄ {3.14, '3.14', ...}

Undef := {undef}

Ref := {v ∈ Scalar | v is a reference}
```

#### Int <: Num <: Str

Str is a proper subset of Scalar. While Str has nearly universal coercions to it (almost any value can be stringified in Perl), coercion capability doesn't imply membership. References stringify to metadata like "HASH(0x00000001f42a)" which fails to satisfy the syntactic preservation test (the string cannot be converted back to the original reference), so references ∉ Str despite being stringifiable.

The complete subtyping chain is Int <: Num <: Str <: Scalar.

When we test membership using S = Str as the reference type, every integer that passes the Int test (survives numification then stringification matching direct stringification) also passes the Num test (survives numification then stringification). However, values like 3.14 pass the Num test but fail the Int test because intification loses fractional information. Therefore Int ⊂ Num (proper subset). Similarly, every Num value survives stringification, but not every Str value survives numification (as demonstrated by "hello"), therefore Num ⊂ Str. The chain emerges naturally from applying the membership test with progressively more permissive coercion semantics.

#### Boolean Types

Boolean is a primitive two-element type containing only the builtin true and false values. Boolean presents an interesting edge case in the formalism. Values like 1, 0, '', and undef can round-trip through boolean coercion and participate in all boolean operations (&&, ||, !, conditionals). However, they fail the `is_bool()` test, which returns true only for the primitive `true` and `false` values themselves.

Whether Boolean fits the formal definition depends on how we classify `is_bool()`. If `is_bool()` ∈ Operations(Boolean), then no coercion produces values satisfying all Boolean operations, making Boolean an exception to the formalism. However, `is_bool()` is arguably a membership predicate (Any → Boolean) rather than an operation on Boolean values, which would mean `is_bool()` ∉ Operations(Boolean). Under this interpretation, Boolean fits the formalism perfectly - values coerce to Boolean and satisfy all actual Boolean operations - though unfortunately it means that `is_bool()` would report false for some values that are members of Boolean under this formalism.

The resolution may also depend on future language evolution, particularly whether operators like `!!` might eventually produce values that satisfy `is_bool()`, providing a coercion path to full Boolean membership. For now, we present both interpretations and acknowledge Boolean as requiring further consideration and future work.

**Note:** See Example 7 for detailed discussion of how Boolean evolved with the introduction of `is_bool()` and the implications for the type system.

#### Reference Types

```
Ref := {v ∈ Scalar | v is a reference}

ScalarRef := {v ∈ Ref | reftype(v) eq 'SCALAR'}
ArrayRef := {v ∈ Ref | reftype(v) eq 'ARRAY'}
HashRef := {v ∈ Ref | reftype(v) eq 'HASH'}
CodeRef := {v ∈ Ref | reftype(v) eq 'CODE'}
GlobRef := {v ∈ Ref | reftype(v) eq 'GLOB'}
Object := {v ∈ Ref | reftype(v) eq 'OBJECT' ∨ blessed(v) is defined}
```

Reference types can use multiple different reference types S for their membership tests. ArrayRef can use S = List (testing whether dereferencing and re-referencing preserves contents), or S = Ref (testing whether the reference nature is preserved through ArrayRef interpretation). This flexibility demonstrates that the formalism accommodates the rich web of coercion relationships in Perl's type system rather than imposing a rigid hierarchy.

**Subtyping:**
- ScalarRef <: Ref
- ArrayRef <: Ref
- HashRef <: Ref
- CodeRef <: Ref
- Object <: Ref

All reference subtypes satisfy both the syntactic and semantic requirements for Ref membership, establishing the subtyping relationships through the general definition.

**Note on Tie, Magic, and Overload:** These mechanisms can alter operational semantics while preserving structural identity. A tied hash maintains `reftype() eq 'HASH'` but may change operation behavior. Type membership depends on whether semantic contracts remain satisfied - a tied hash that violates expected HashRef operation contracts (e.g., non-idempotent `keys`) would fail semantic fulfillment despite passing structural tests. This demonstrates why both syntactic preservation and semantic fulfillment components are necessary for type membership.

**Note on Object Types:** Native class objects (Perl 5.38+ `feature 'class'`) and traditional blessed references have different type relationships:

**Native Class Objects** are opaque references that belong only to Object:
```
ClassObject := {v ∈ Ref | v is a native class instance}
ClassObject <: Object <: Ref
```
These cannot be dereferenced as their underlying storage type, even though they may be internally implemented using hash or array storage.

**Blessed References** are union types satisfying both Object and their underlying reference type:
```
BlessedHashRef := Object ∩ HashRef
BlessedArrayRef := Object ∩ ArrayRef
BlessedScalarRef := Object ∩ ScalarRef
BlessedCodeRef := Object ∩ CodeRef
BlessedGlobRef := Object ∩ GlobRef
```

A blessed hashref satisfies both Object contracts (method calls, `blessed()`, `isa()`) and HashRef contracts (dereferencing with `$obj->{key}`, `keys %$obj`). Therefore:
- `BlessedHashRef ∈ Object` ✓
- `BlessedHashRef ∈ HashRef` ✓

This distinction matters for type checking: blessed references maintain the semantic contracts of their implementation type, while native class objects are opaque and expose only their class interface.

### List Types

```
List := {v | v is a sequence of zero or more values in list context}
     = {(), (1), (1,2), ('a','b','c'), ...}

Array := {v | v is a persistent ordered container with array operations}
Hash := {v | v is a persistent key-value container with hash operations}
```

List represents ephemeral sequences that exist during evaluation in list context, while Array and Hash represent persistent containers. The distinction matters because Arrays and Hashes have operations (like push, keys) that Lists do not support, yet Arrays and Hashes can produce List values when evaluated in list context.

**Subtyping:**
- Array <: List (arrays produce list values in list context)
- Hash <: List (hashes flatten to list values in list context)

### Other Types

```
Code := {v | v is a subroutine value}
Glob := {v | v is a symbol table entry}
```

We know Code and Glob exist definitionally because coercions exist to their reference types. CodeRefs can be created directly using anonymous subroutine syntax (sub { }), independent of named Code subroutines. Glob presents an interesting case because globs are created implicitly by the symbol table rather than through explicit value construction, and GlobRef can only be created by taking a reference to an existing Glob using the reference operator.

While you can trigger glob creation using string eval, this is a side effect that leverages the same implicit symbol table construction rather than true explicit creation.

Globs themselves can be accessed directly using bareword syntax like *STDIN or *Package::name, making the Glob the primary form and GlobRef the derived reference form. This pattern is similar to ScalarRef, which also can only be created by referencing an existing scalar rather than through direct construction.

### Bottom Type

```
None := ∅
```

**None** represents computations that never produce a value (die, exit, infinite loops). This is the empty type containing no values.

**Property:** ∀T: None <: T (the empty set is a subset of all sets)

## Complete Type Hierarchy

```
Unknown / Any (⊤ = V)
├── Scalar
│   ├── Undef
│   ├── Boolean
│   ├── Str
│   │   └── Num
│   │       └── Int
│   ├── DualVar (in Scalar but not in Str or Num)
│   └── Ref
│       ├── Object
│       ├── ScalarRef
│       ├── ArrayRef
│       ├── HashRef
│       ├── CodeRef
│       └── GlobRef
├── List
│   ├── Array
│   └── Hash
├── Code
├── Glob
└── None (⊥ = ∅)
```

This hierarchy shows Scalar as a concrete type containing various scalar value categories. DualVars sit in Scalar but outside the Str and Num branches, demonstrating that Scalar is genuinely broader than its more specialized subtypes. The reference types form another branch under Scalar, while List types form a separate category for sequence values.

## Definitional Layering and Circularity

The type system definitions form a carefully layered structure:

**Layer 0: Coercions** - Judgment `v ⇓^T u` defined inductively over value structure, independent of type membership.

**Layer 1: Operational Semantics** - Evaluation rules `Γ ⊢ e ⇓^ctx result` defined using coercions. Operations(T) derived mechanically from these rules.

**Layer 2: Observational Equivalence** - `v₁ ≡ v₂` defined using primitive equality (==, eq) on coercion results.

**Layer 3: Type Membership** - Defined using syntactic preservation and semantic fulfillment.

### The Circularity Issue

**Base types Scalar and List are mutually circular:** Scalar membership may use List as reference type, and vice versa. This reflects Perl's context coercion semantics where scalars become lists and lists become scalars.

We conjecture this circular system has a unique consistent solution via Knaster-Tarski fixed-point theorem. The key property enabling this is that operation contracts depend only on syntactic preservation (Layer 0 coercions), not on type membership, making the refinement operator monotone.

**Derived types are stratified:** Once Scalar and List are established:
1. Str is defined using Scalar as reference type
2. Num is defined using Str as reference type
3. Int is defined using Num as reference type
4. Ref, Boolean, etc. use Scalar
5. Array, Hash use List

This creates dependency chain: Scalar/List → Str → Num → Int, avoiding circularity among derived types.

**Important distinction:** The reference type in a type's *definition* determines dependencies. Post-definition, membership can be *tested* using any appropriate reference type (e.g., Str membership testable via Num) - this is verification, not definition.

**Full mechanization** (proving fixed-point exists, F is monotone, lfp(F) matches Perl semantics) is left as future work. For this paper, we proceed assuming consistency, supported by: (1) Perl's stable semantics, (2) concrete proofs below work in practice, (3) no contradictions found.

See Future Work section for detailed mechanization roadmap.

## Key Theorems

### Theorem 1: Syntactic Preservation Is Necessary for Membership

**Statement:**
```
∀v ∈ V, ∀T: (v ∈ T) ⟹ ∃S: SyntacticPreservation(v, T, S)
```

**Proof:** Direct from [Type-Membership] inference rule, which requires SyntacticPreservation as a premise.

### Theorem 2: Semantic Fulfillment Is Necessary for Membership

**Statement:**
```
∀v ∈ V, ∀T: (v ∈ T) ⟹ SemanticFulfillment(v, T)
```

**Proof:** Direct from [Type-Membership] inference rule, which requires SemanticFulfillment as a premise.

### Theorem 3: Both Components Are Necessary

**Statement:**
```
¬(∀v, T: (∃S: SyntacticPreservation(v, T, S)) ⟹ v ∈ T)
∧
¬(∀v, T: SemanticFulfillment(v, T) ⟹ v ∈ T)
```

Neither syntactic preservation alone nor semantic fulfillment alone is sufficient for type membership. Both conditions must hold.

**Proof by counterexample:**

*Syntactic preservation insufficient:* The string "NaN" demonstrates syntactic preservation without semantic fulfillment for Num. When tested with S = Str:
```
"NaN" ⇓^Num NaN    NaN ⇓^Str "NaN"
"NaN" ⇓^Str "NaN"
"NaN" ≡ "NaN"
-------------------------------------
SyntacticPreservation("NaN", Num, Str)
```

However, "NaN" fails semantic fulfillment because it violates multiple numeric operation contracts:

*Equality contract violation:*
```
v = "NaN", v ⇓^Num NaN
(NaN == NaN) = false  (violates reflexivity)
```

*Subtraction contract violation:*
```
v₁ = v₂ = "NaN", both ⇓^Num NaN
(NaN - NaN) = NaN ≠ 0  (expected: v - v = 0)
```

Since at least one operation in Operations(Num) has its contract violated:
```
¬(∀op ∈ Operations(Num): ∃S: Contract_op(Num, S))
--------------------------------------------------
¬SemanticFulfillment("NaN", Num)
```

Therefore "NaN" ∉ Num despite passing the syntactic test.

*Semantic fulfillment without syntactic preservation:* Conversely, values like "hello" fail even the syntactic test for Num:
```
"hello" ⇓^Num 0    0 ⇓^Str "0"
"hello" ⇓^Str "hello"
"0" ≢ "hello"
---------------------------------------
¬SyntacticPreservation("hello", Num, Str)
```

Both components serve distinct and essential roles in determining type membership. ∎

### Theorem 4: Subtyping Transitivity

**Statement:**
```
∀A, B, C: (A <: B) ∧ (B <: C) ⟹ (A <: C)
```

**Proof:** By [Subtyping-Transitive] inference rule. Alternatively, by expansion:

1. From A <: B, we have by [Subtyping]:
   ```
   ∀v ∈ V: (v ∈ A ⟹ v ∈ B)
   ∀v ∈ A: ∀op ∈ Operations(B): ∃S: Contract_op(B, S) holds for v
   ```

2. From B <: C, we have:
   ```
   ∀v ∈ V: (v ∈ B ⟹ v ∈ C)
   ∀v ∈ B: ∀op ∈ Operations(C): ∃S: Contract_op(C, S) holds for v
   ```

3. By set transitivity:
   ```
   ∀v ∈ V: (v ∈ A ⟹ v ∈ B) ∧ (v ∈ B ⟹ v ∈ C)
   -----------------------------------------------
   ∀v ∈ V: (v ∈ A ⟹ v ∈ C)
   ```

4. For operation contracts, since v ∈ A ⟹ v ∈ B, and values in B satisfy Operations(C) contracts:
   ```
   ∀v ∈ A: ∀op ∈ Operations(C): ∃S: Contract_op(C, S) holds for v
   ```

5. Therefore by [Subtyping], A <: C. ∎

### Lemma 1: Int <: Num

**Statement:**
```
Int <: Num
```

**Proof:** We must show (1) Int ⊆ Num and (2) values in Int satisfy Operations(Num) contracts.

*Part 1: Int ⊆ Num*

Let v ∈ Int. By definition of Int membership:
```
∃S: SyntacticPreservation(v, Int, S)
SemanticFulfillment(v, Int)
-----------------------------------------
v ∈ Int
```

We show v ∈ Num using S = Str as reference type:
```
v ⇓^Int i    i ⇓^Str s₁
v ⇓^Str s₂
s₁ ≡ s₂
------------------------
SyntacticPreservation(v, Int, Str)
```

For numeric coercion:
```
v ⇓^Num n    n ⇓^Str s₃
```

Since v ∈ Int, we have v ⇓^Int i where i is an integer value. By coercion composition, v ⇓^Num i (integers are numbers). Therefore:
```
v ⇓^Num i    i ⇓^Str s₁    (from Int membership)
v ⇓^Str s₂
s₁ ≡ s₂
--------------------------
SyntacticPreservation(v, Num, Str)
```

The syntactic preservation for Num holds because integer coercion is more restrictive than numeric coercion (intification truncates, but the reverse - viewing an integer as a number - is lossless).

*Part 2: Operations(Num) contracts*

Operations(Num) = {+, -, *, /, ==, !=, <, >, <=, >=, ...}. Since v ∈ Int satisfies all integer operation contracts and integer operations are specializations of numeric operations, v must satisfy numeric operation contracts. For example:
```
v₁, v₂ ∈ Int ⟹ (v₁ ⇓^Num n₁) ∧ (v₂ ⇓^Num n₂) ∧ (n₁ + n₂ ⇓^Num n₃)
```

Since integers are closed under numeric addition and satisfy numeric equality contracts, all Operations(Num) contracts hold.

Therefore Int <: Num. ∎

### Lemma 2: Num <: Str

**Statement:**
```
Num <: Str
```

**Proof:** We must show (1) Num ⊆ Str and (2) values in Num satisfy Operations(Str) contracts.

*Part 1: Num ⊆ Str*

Let v ∈ Num. By definition, v has lossless numeric interpretation. We show v ∈ Str:

```
v ⇓^Str s    s ⇓^Str s    (string coercion is idempotent)
s ≡ s
----------------------------
SyntacticPreservation(v, Str, Str)
```

More precisely, using S = Num as reference type for testing Str membership:
```
v ⇓^Str s    s ⇓^Num n₁
v ⇓^Num n₂
n₁ ≡ n₂
------------------------
SyntacticPreservation(v, Str, Num)
```

Since v ∈ Num, we know v ⇓^Num n where n preserves v's numeric content. When we stringify this to s and numify back, we get n again because numeric strings round-trip through stringification. The value "42" demonstrates: "42" ⇓^Str "42", "42" ⇓^Num 42, and the original value has v ⇓^Num 42, so the round-trip succeeds.

*Part 2: Operations(Str) contracts*

Operations(Str) = {., eq, ne, lt, gt, le, ge, length, substr, ...}. Values in Num have string representations that satisfy string operation contracts. For example:
```
v₁, v₂ ∈ Num ⟹ (v₁ ⇓^Str s₁) ∧ (v₂ ⇓^Str s₂) ∧ (s₁ eq s₂) correctly distinguishes values
```

String concatenation, equality, and other string operations behave meaningfully on numeric string representations.

Therefore Num <: Str. ∎

### Lemma 3: Str <: Scalar

**Statement:**
```
Str <: Scalar
```

**Proof:** We must show (1) Str ⊆ Scalar and (2) values in Str satisfy Operations(Scalar) contracts.

*Part 1: Str ⊆ Scalar*

Let v ∈ Str. By definition, v has lossless string interpretation. We show v ∈ Scalar:

```
v ⇓^Scalar u    u ⇓^ScalarRef r₁
v ⇓^ScalarRef r₂
r₁ ≡ r₂
-------------------------------
SyntacticPreservation(v, Scalar, ScalarRef)
```

Since strings are scalar values by Perl's fundamental semantics (they can be stored in scalar variables and maintain identity), the syntactic preservation holds. The value v, when treated as a scalar and referenced, produces the same reference as when directly referenced.

*Part 2: Operations(Scalar) contracts*

Operations(Scalar) includes scalar assignment, scalar context evaluation, and reference operations. Values in Str satisfy these because strings are inherently scalar - they maintain singular value identity through scalar operations.

Therefore Str <: Scalar. ∎

### Corollary: Int <: Num <: Str <: Scalar

By transitivity (Theorem 4):
```
Int <: Num (Lemma 1)    Num <: Str (Lemma 2)
--------------------------------------------
Int <: Str

Int <: Str    Str <: Scalar (Lemma 3)
-------------------------------------
Int <: Scalar
```

This establishes the complete subtyping chain for scalar numeric/string types. ∎

## Examples and Applications

### Example 1: Why "42" ∈ Num

**Syntactic component:** Using S = Str as the reference type, we test whether the detour path through Num matches the direct path to Str. The detour interprets "42" as a number (getting the numeric value 42), then stringifies that (getting "42" again). The direct path simply treats "42" as a string (getting "42"). Since both paths produce "42", syntactic preservation holds: C("42") ≡ id_Str("42").

**Semantic component:** The value "42" satisfies all numeric operation contracts. Numeric equality correctly distinguishes it from other values (42 == 42 is true, 42 == 43 is false). Arithmetic operations produce meaningful results (42 + 1 = 43). The value behaves as a valid representation of the number forty-two in all numeric contexts. Therefore semantic fulfillment holds.

Since both components are satisfied, "42" ∈ Num. The value survives numeric interpretation structurally and participates meaningfully in numeric operations behaviorally.

### Example 2: Why "hello" ∉ Num

**Syntactic component:** Using S = Str, the detour path interprets "hello" as a number (which in Perl yields zero because "hello" cannot be parsed numerically), then stringifies that zero to get "0". The direct path treats "hello" as a string, giving "hello". Since "0" ≢ "hello", syntactic preservation fails: C("hello") ≢ id_Str("hello").

The syntactic component already fails, so we need not check the semantic component. The value "hello" ∉ Num because it loses essential information when forced through numeric interpretation. The original string "hello" and the stringified result "0" are observationally distinct, demonstrating that numeric coercion destroyed information about the value's identity.

### Example 3: Why "NaN" ∉ Num Despite Syntactic Preservation

**Syntactic component:** Using S = Str, the detour path interprets "NaN" as a number (which produces the IEEE 754 NaN floating-point value), then stringifies that back to "NaN". The direct path treats "NaN" as a string, giving "NaN". Since both paths produce the string "NaN", syntactic preservation appears to hold: C("NaN") ≡ id_Str("NaN").

**Semantic component:** However, "NaN" fails to satisfy numeric operation contracts. Consider the semantic contract for numeric equality (==): the operation should correctly distinguish between distinct numeric values according to their numeric interpretations, and equality should be reflexive (any value equals itself). But under IEEE 754 semantics, NaN ≠ NaN. This violates reflexivity and demonstrates that NaN cannot fulfill the contracts expected of valid numeric values.

More fundamentally, NaN is semantically defined as "Not a Number." It is a special marker value in the IEEE floating-point standard that explicitly represents the absence of valid numeric content, produced by undefined operations like zero divided by zero. While NaN participates in the syntactic machinery of numeric representation, its semantic purpose is to mark failure of numeric interpretation.

Since the semantic component fails despite syntactic preservation, "NaN" ∉ Num. However, "NaN" ∈ Str because it satisfies both the syntactic and semantic requirements for string membership (it has a stable string representation and behaves correctly under string operations).

This example demonstrates why both components are essential. Syntactic preservation alone is insufficient to establish type membership. Values must also satisfy the behavioral contracts that define what it means to be a member of the type.

### Example 4: Why DualVars Demonstrate Scalar as a Concrete Type

A DualVar is a Perl value with independent string and numeric interpretations. For example, we can create a DualVar that is numerically 42 but stringifies to "hello" using Scalar::Util::dualvar.

**Testing membership in Num:** Using S = Str as the reference type, the detour path numifies the DualVar (getting 42), then stringifies that (getting "42"). The direct path stringifies the DualVar (getting "hello"). Since "42" ≢ "hello", syntactic preservation fails. Therefore DualVar ∉ Num.

**Testing membership in Str:** Using S = Num as the reference type, the detour path stringifies the DualVar (getting "hello"), then numifies that (getting zero because "hello" is not numeric). The direct path numifies the DualVar (getting 42, its numeric aspect). Since 0 ≠ 42, syntactic preservation fails. Therefore DualVar ∉ Str either.

**Testing membership in Scalar:** Testing membership in Scalar: Using S = ScalarRef as the reference type, we test whether the DualVar maintains its identity through scalar interpretation. Taking a reference to the DualVar gives us a ScalarRef that points to the value with both its string aspect (“hello”) and numeric aspect (42) intact. The direct path (immediately taking a reference) and the detour path (interpreting as Scalar then taking a reference) both produce the same ScalarRef pointing to the same dual-natured value. Therefore syntactic preservation holds.

Therefore DualVar ∈ Scalar while DualVar ∉ Num and DualVar ∉ Str. This demonstrates that Scalar is a genuine type with its own membership criteria, containing values that do not belong to its more specialized subtypes. Scalar is not merely an abstract context category but a concrete type characterized by the property of maintaining singular value identity through scalar operations.

### Example 5: Roman Numerals and Semantic Contract Violation

Consider the strings "IV" and "V" representing Roman numerals with clear, unambiguous numeric interpretations: "IV" means four and "V" means five. When we test these against Num:

**Syntactic component:** Using S = Str, both "IV" and "V" fail the round-trip test. Perl's numeric coercion does not recognize Roman numerals and instead coerces both to zero (because they don't begin with digits). After stringification, we get "0" in both cases, which is not equivalent to the original strings "IV" and "V". Therefore both values are correctly excluded from Num by the syntactic test alone.

**Hypothetical semantic analysis:** Even if we had a coercion that preserved the syntactic structure, there would be a semantic contract violation. Consider the operation "IV" == "V" with hypothetical Roman numeral coercion. Under correct Roman numeral interpretation, four does not equal five, so the result should be false. However, Perl's actual numeric coercion produces zero for both, then compares zero == zero, yielding true. This violates the semantic contract of numeric equality: the operation should correctly distinguish distinct numeric values according to their numeric interpretations.

This example illustrates that semantic contracts capture what operations are intended to do, not merely what they mechanically compute. Even though "IV" and "V" have clear numeric meanings, Perl's coercion system does not preserve those meanings, so the values cannot belong to Num.

### Example 6: Reference Types and Structural Preservation

Consider testing whether an array reference `$ref = [1, 2, 3]` belongs to ArrayRef. We can use multiple reference types to test this.

**Using S = List:** The detour path interprets `$ref` as an ArrayRef, then dereferences it to produce the list (1, 2, 3). The direct path interprets `$ref` as a List by dereferencing, also producing (1, 2, 3). Both paths yield the same list contents, so syntactic preservation holds. Furthermore, `$ref` satisfies all operations expected of ArrayRef (dereferencing, element access, array methods). Therefore `$ref ∈ ArrayRef` when tested against List.

**Using S = Ref:** The detour path interprets `$ref` through ArrayRef's semantics, then views it as a generic Ref (recognizing it as a reference). The direct path views `$ref` as a Ref immediately (recognizing it as a reference). Both paths confirm the reference nature of the value, so syntactic preservation holds through a different route. Combined with semantic fulfillment, this alternative test also confirms `$ref ∈ ArrayRef`.

This example demonstrates the flexibility of reference type choice. ArrayRef can be characterized relative to List (through dereferencing semantics) or relative to Ref (through reference identity semantics). The formalism accommodates multiple valid characterizations of the same type, reflecting the rich interconnections in Perl's coercion system.

### Example 7: Boolean as a Primitive Type with Explicit Membership

Boolean is a primitive two-element type containing only the builtin `true` and `false` values introduced in Perl 5.36. The `is_bool()` predicate serves as the authoritative membership test, distinguishing Boolean members from values that merely coerce to boolean.

**Why `true` ∈ Boolean:**

**Syntactic component:** Using S = Scalar as the reference type, the value `true` maintains its identity through boolean interpretation. Storing `true` in a scalar variable and retrieving it preserves the value's boolean nature.

**Semantic component:** The semantic contract for Boolean membership is `is_bool()`. When we evaluate `is_bool(true)`, it returns true, confirming membership. The value `true` satisfies all boolean operations correctly: negation yields `false`, conditional tests treat it as truthy, and boolean operators behave as expected. Therefore `true` ∈ Boolean.

**Why `false` ∈ Boolean:**

Following the same analysis, `is_bool(false)` returns true, confirming membership. The value `false` satisfies boolean operation contracts as the canonical false value. Therefore `false` ∈ Boolean.

**Why 1 ∉ Boolean Despite Behaving Like True:**

**Syntactic component:** The value 1 can be stored in scalar variables and participates in boolean coercion without difficulty. When evaluated in boolean context, 1 behaves identically to `true` - it's truthy, negates to false, and works correctly in all boolean operations.

**Semantic component failure:** However, 1 fails the `is_bool()` semantic contract. When we evaluate `is_bool(1)`, it returns false. This demonstrates that 1 is not a Boolean member despite its behavioral equivalence to `true` in boolean contexts. The value 1 belongs to Int (and by extension Num and Str through the subtyping chain), and it coerces to Boolean when needed, but it is not itself a Boolean.

Therefore 1 ∉ Boolean. The distinction between membership and coercion is critical here. The value 1 can participate in boolean operations through coercion, but it is not a member of the Boolean type.

**Why 0 ∉ Boolean:**

Similarly, `is_bool(0)` returns false, excluding 0 from Boolean membership despite 0 being falsy and behaving like `false` in boolean contexts. The value 0 belongs to Int/Num/Str and coerces to Boolean, but is not a Boolean member.

**Why '' ∉ Boolean:**

The empty string fails the membership test: `is_bool('')` returns false. While '' is falsy and behaves like `false` in boolean operations, it belongs to Str and is not a Boolean member.

**Why undef ∉ Boolean:**

The undefined value also fails: `is_bool(undef)` returns false. Though undef is falsy, it belongs to the Undef type and is not a Boolean member.

**Observational Equivalence vs. Type Membership:**

This example demonstrates an important distinction in the formalism. Observational equivalence describes behavioral similarity under operations - the value 1 behaves like `true` in boolean contexts, and `true` behaves like 1 in numeric contexts (numifying to 1). However, observational equivalence does not imply type membership.

The `is_bool()` predicate serves as an explicit semantic contract that distinguishes the primitive Boolean type from values that merely exhibit boolean behavior through coercion. This makes Boolean one of the clearest examples in Perl's type system where an explicit membership predicate (semantic contract) takes precedence over behavioral equivalence (syntactic preservation).

**Historical Context:**

Before Perl 5.36 introduced builtin boolean primitives, there was no way to distinguish "true boolean values" from "values that behave as booleans." Under a pure coercion-based formalism without `is_bool()`, Boolean would have been defined as {1, 0, '', undef} - the values that preserve their boolean identity through round-trip coercion tests. The introduction of `is_bool()` transformed Boolean from a behavioral classification into a true primitive type with exactly two members, demonstrating how Perl's type system can evolve through the addition of new semantic contracts.

## Related Work

### Latent Type Systems

Perl's type system is both **latent** and **dynamic**. It is **latent** because types emerge as side effects of operators rather than from explicit declarations or annotations. It is **dynamic** because type relationships are determined at runtime through coercion and operational behavior, not through compile-time checking or inference.

**Cartwright & Fagan (1991)** introduced soft typing, where types are inferred for dynamically-typed programs to enable optimization and error detection without requiring annotations. Our formalization differs in that we characterize the implicit types present in Perl's semantics rather than inferring static approximations. Where soft typing projects static types onto dynamic code, we extract the latent type structure inherent in the operational semantics.

**Tobin-Hochstadt & Felleisen (2008, 2010)** developed occurrence typing for Typed Racket, using conditional tests as type refinements. Our syntactic preservation tests play a similar role - values "prove" their type membership by surviving round-trip coercions. However, occurrence typing refines types based on predicates in conditional branches, while our tests characterize type membership itself through operational behavior.

### Coercion-Based Type Systems

**Henglein (1994)** formalized coercions as morphisms in a categorical framework for type-directed compilation. Our coercion judgments (v ⇓^T u) share the compositional structure but serve a different purpose: rather than implementing safe casts between statically-known types, our coercions define type boundaries through round-trip preservation tests.

**JavaScript type systems** (TypeScript, Flow) face similar challenges with pervasive coercion. **Bierman et al. (2014)** formalized TypeScript's gradual structural typing, which allows `any` to interact with all types. Our Unknown/Any types serve similar roles, but Perl's coercion semantics are more aggressive and value-transforming than JavaScript's, requiring both syntactic preservation and semantic fulfillment components.

**Siek & Taha (2006, 2007)** introduced gradual typing, mixing static and dynamic checking with a consistency relation. Our formalism provides foundations for a gradual type system for Perl: the Unknown type corresponds to the dynamic type ?, and our membership conditions could become runtime checks at type boundaries. The key difference is that gradual typing typically starts with a static type system and adds dynamic escapes, while we extract static structure from existing dynamic semantics.

### Subtyping and Behavioral Compatibility

**Liskov & Wing (1994)** formalized behavioral subtyping through the substitution principle. Our subtyping definition (A <: B requires A ⊆ B and operational substitutability) directly implements this principle. The semantic fulfillment component ensures that subtypes satisfy all operation contracts of their supertypes, formalizing "programs that reason about B should work correctly when given elements of A."

**Cardelli (1988)** distinguished structural typing (membership determined by structure) from nominal typing (membership by declaration). Perl's latent types are hybrid: syntactic preservation is structural (does the value have compatible structure through coercion?), while semantic fulfillment is behavioral (does it satisfy operational contracts?). This combination is necessary because Perl's aggressive coercion makes pure structural typing insufficient - "hello" has numeric structure (coerces to 0) but doesn't meaningfully participate in numeric operations.

### Contract Systems and Behavioral Types

**Findler & Felleisen (2002)** introduced higher-order contracts for enforcing behavioral specifications at module boundaries. Our operation contracts play a similar role but are embedded in type membership rather than enforced at boundaries. A value belongs to Num only if it satisfies numeric operation contracts; violations exclude the value from the type rather than raising contract errors.

**Typed Racket's refinement types** allow predicates to refine base types (e.g., `{x : Int | x > 0}`). Our semantic contracts are similar in spirit but more fundamental - they don't refine types, they define them. The distinction between "42" ∈ Num and "hello" ∉ Num is determined by contract satisfaction, not declared refinements.

### Duck Typing and Structural Compatibility

**TypeScript (Bierman et al. 2014)** uses structural typing where compatibility is determined by having the required properties and methods. Both systems embody duck typing ("if it walks like a duck..."), but the mechanisms differ:

- **TypeScript:** Does this object have methods named `foo` and `bar` with compatible signatures?
- **Perl (this work):** Does this value survive interpretation through type T and satisfy T's operation contracts?

TypeScript's structure is about interface shape, while Perl's is about coercion behavior. A TypeScript object `{x: number}` is structurally compatible with `{x: number, y: string}` (width subtyping). In Perl, "42" ∈ Num because it survives numeric interpretation and behaves correctly under numeric operations.

**Go's interfaces** determine compatibility by method sets but use nominal matching (explicit declarations). Go and Perl both care about behavioral substitutability, but Go checks at compile time based on declared signatures, while Perl's types emerge from runtime coercion patterns.

### Dynamic Languages with Type Systems

**Python's gradual typing (PEP 484, mypy)** adds optional static annotations to a dynamically-typed language. The key difference from our work is direction: Python overlays static types on dynamic code, while we extract the latent type structure already present in Perl's operational semantics. Python's type checker ignores runtime coercion behavior, while our types are defined by it.

**Ruby's type systems** (RDL, Sorbet, Steep) similarly add static analysis to a dynamic language. Ruby's coercion is less pervasive than Perl's (no automatic string-to-number), making these systems closer to traditional gradual typing. Our approach is distinct in that Perl's coercion system is so fundamental that types must be characterized through it rather than layered atop it.

**JavaScript's ToPrimitive and ToString coercions** exhibit similar complexity to Perl's. Recent work on JavaScript type systems (TAJS, TypeScript, Flow) handles coercion through union types and type guards. Our approach differs by making coercion the definitional mechanism: types are characterized by which coercions preserve identity, rather than treating coercion as conversions between pre-existing types.

### Fixed-Point Semantics

**Knaster-Tarski theorem** provides existence and uniqueness of fixed points for monotone operators on complete lattices. We conjecture our type system (specifically the circular Scalar/List definitions) forms such a fixed point. This technique is standard in domain theory (**Scott & Strachey 1971**) but novel in application to latent type characterization.

**Recursive types (Courcelle 1983, Amadio & Cardelli 1993)** allow types to refer to themselves (e.g., `μα. Unit + α × α` for lists). Our circularity is different: not individual recursive types, but mutual dependence between base types where Scalar may use List as reference type and vice versa. The fixed-point structure emerges from the membership definition itself.

### Type Inference for Dynamic Languages

**Cartwright & Fagan (1991), Henglein & Rehof (1995)** developed type inference for Scheme, inferring static types for dynamic code. **An, Chaudhuri & Foster (2011)** inferred types for Ruby using constraint solving. These systems infer static approximations of runtime types.

Our work is descriptive rather than inferential - we characterize the types Perl already has through its operational semantics. A type inference system could build on our formalism (as discussed in Future Work), using our membership conditions as constraints, but the formalism itself describes existing structure rather than inferring new annotations.

### Observational Equivalence

Our observational equivalence (v₁ ≡ v₂ when they produce identical results under all interpretation coercions) relates to **Morris's (1968)** contextual equivalence and **Abramsky's (1990)** applicative bisimulation. The key difference is scope: we consider only interpretation coercions (⇓^Str, ⇓^Num, ⇓^Bool) rather than all possible contexts. This restricted notion suffices for type characterization because these coercions are the foundation of Perl's operational semantics.

### Summary and Contributions

This formalization makes three novel contributions relative to prior work:

1. **Dual-component type membership:** Combining syntactic preservation (structural round-trip tests) with semantic fulfillment (operational contracts) captures types in a language where coercion is pervasive and value-transforming. Pure structural approaches fail for values like "NaN" that have appropriate structure but meaningless behavior.

2. **Fixed-point characterization of circular base types:** Scalar and List are mutually circular through context coercions, resolved via conjectured fixed-point semantics. This differs from recursive types or gradual typing's consistency relations.

3. **Formalization of latent types from operational semantics:** Rather than inferring static approximations or adding optional annotations, we extract the type structure implicit in Perl's runtime behavior, providing foundations for tools while preserving semantic fidelity.

The techniques - coercion-based membership tests, contract-based behavioral types, fixed-point resolution of circularity - may apply to other dynamic languages with complex coercion (JavaScript, Python, Ruby), making this work relevant beyond Perl.

## Implementation Notes

**Note on Enforcement:** This formalism describes Perl's implicit type structure, not enforced constraints. Perl's runtime happily executes operations that violate semantic contracts (e.g., `"hello" == "goodbye"` executes but violates numeric equality's contract). The types defined here represent what values *should* be used with which operations for semantically meaningful results, not what Perl prevents. This model provides a foundation for optional static analysis tools that could warn about semantic contract violations.

### Type Checking Strategy

A static analyzer for Perl could use this formalization for several purposes. Type inference would start with Unknown for each expression and progressively narrow to more specific types based on the operations applied and coercions performed. Error detection would flag cases where operations are applied to values that fail either the syntactic preservation test or the semantic fulfillment requirements for the expected type. Optimization opportunities arise when type information proves that certain runtime coercions or checks are redundant because the values provably satisfy the required type constraints.

### Coercion Rules

The formalization assumes well-defined coercion functions with specific semantics. In Perl's actual implementation, the coercion rules are:


**To Boolean (Boolean):**
- `true`, `false` → to themselves (identity)
- 0, '', undef → false
- All other values → true

**To String (Str):**
- Numbers → decimal representation ("42", "3.14")
- References → "TYPE(0xADDRESS)" format (metadata, not recoverable)
- undef → "" (empty string)
- Objects → stringification overload if defined, otherwise reference format
- Booleans → "1" or "" (the empty string)

**To Number (Num):**
- Numeric strings → parsed value ("42" → 42, "3.14" → 3.14)
- Non-numeric strings → 0 with warning ("hello" → 0)
- References → numeric interpretation of memory address
- undef → 0
- Objects → numification overload if defined, otherwise address
- Booleans → 1 or 0

**To Integer (Int):**
- Numbers → truncate toward zero (3.14 → 3, -2.7 → -2)
- Same rules as Num for initial coercion, then truncation

These coercion semantics determine which values pass the syntactic preservation tests for each type, establishing the type boundaries that the formalization characterizes abstractly.

### Context Propagation

Context (Scalar, List, Void) propagates through expressions and affects evaluation:

```perl
my $x = foo() + 1;    # foo() called in Scalar context
my @y = (foo(), 2);   # foo() called in List context
foo();                # foo() called in Void context
```

The formalization focuses primarily on scalar types where context effects are simpler. List context introduces additional complexity because functions can return different numbers of values depending on context, and arrays/hashes behave differently in scalar versus list context. A complete treatment would need to incorporate context as a parameter to type judgments, perhaps written as Γ ⊢ e : T in context C where C ∈ {Scalar, List, Void}. This extension is left for future work, though the foundational principles of syntactic preservation and semantic fulfillment would still apply.

## Future Work

This formalization provides a foundation for understanding Perl's latent type system, but several significant extensions remain.

### Mechanized Proof of Type System Consistency

The most critical open question is formal proof that the circular definitions of Scalar and List have a unique consistent solution. This would require:

1. **Fixed-point formalization** - Define candidate type systems Σ = (∈_Scalar, ∈_List), partial order Σ₁ ⊑ Σ₂, and refinement operator F(Σ) computing new memberships.

2. **Monotonicity proof** - Show F is monotone: Σ₁ ⊑ Σ₂ ⟹ F(Σ₁) ⊑ F(Σ₂). Key insight: contracts depend only on syntactic preservation (Layer 0), not on membership, making F monotone.

3. **Fixed-point correspondence** - Verify Perl's semantics corresponds to lfp(F) via Knaster-Tarski theorem.

4. **Mechanization** - Implement in Coq/Agda with 12-week roadmap: formalize value syntax (weeks 1-2), operational semantics (weeks 3-4), type membership (weeks 5-6), prove monotonicity and apply Knaster-Tarski (weeks 7-10), verify against Perl (weeks 11-12).

**Estimated effort:** 3 months core mechanization, 6 months full system.
**Target venue:** ICFP, POPL, or Journal of Functional Programming.

### Practical Applications

**Static type checker for Perl** - Analyze code without running it, detect type errors, warn about semantic contract violations. Implementation: parse Perl, infer types using membership conditions, report violations.

**CPAN case study** - Apply type checker to representative modules (Moose, DBI, Catalyst), measure precision/recall, identify common bug patterns, validate formalism matches Perl semantics.

**Optimization opportunities** - Use type information to eliminate redundant coercions, generate specialized monomorphic code, perform dead code elimination for impossible type combinations.

### Extensions

**Metatheory** - Prove progress and preservation theorems, analyze decidability of type membership, develop algorithmic type checking.

**Gradual typing** - Connect Unknown/Any types to gradual typing theory, design optional type annotation system for Perl, implement runtime checks at type boundaries.

**Context-sensitive types** - Fully formalize Scalar/List/Void context effects, define context-indexed types `v ∈_ctx T`, handle lvalue vs rvalue contexts.

**DualVars, Magic, Overloading** - Extend formalism to handle values with independent string/numeric aspects, tied variables affecting type semantics, operator overloading.

### Publication Timeline

- **Workshop paper (6 months):** Current formalism with fixed-point sketch, concrete examples, case studies. Target: ECOOP, OOPSLA workshops.

- **Journal paper (12 months):** Mechanized consistency proof, comprehensive metatheory, practical type checker with CPAN evaluation. Target: JFP, TOPLAS.

- **Long-term (2-3 years):** Full gradual typing system for Perl, production-quality type checker, integration with Perl core. Target: ICFP, POPL.

The techniques developed here - formalizing latent types through coercion and contracts, handling circular definitions via fixed points - may apply to other dynamically-typed languages with complex coercion (JavaScript, Python, Ruby), making this work relevant beyond Perl.

## Conclusion

This formal model captures Perl's type system through two essential and complementary principles:

**Syntactic preservation through coercion** defines type membership structurally. A value belongs to a type when it can survive interpretation through that type's semantic domain without losing essential information, as demonstrated by the test C(v) ≡ id_S(v) for some reference type S. This captures the first-order question: does the value have the right structure to be viewed through this type's lens?

**Semantic fulfillment of operational contracts** defines type membership behaviorally. A value must also satisfy all the contracts that operations on the type expect, ensuring meaningful participation in the type's behavioral interface. This captures the second-order question: does the value behave correctly when used as this type?

Together, these principles provide a complete characterization of type membership that explains both why certain Perl idioms work naturally (numeric strings are numbers because they survive numeric coercion and behave correctly in numeric operations) and why others fail (arbitrary strings don't support numeric operations meaningfully, references don't round-trip through string representation, "NaN" doesn't fulfill numeric contracts despite syntactic preservation).

The model establishes a rich type lattice with V at the top containing all values, Scalar and List as major categorical divisions, and progressively more specialized types like Str, Num, Int, and various reference types forming a hierarchy through subset relationships that emerge from the membership tests. Special cases like DualVars prove that Scalar is a concrete type distinct from its subtypes, while edge cases like "NaN" demonstrate the necessity of both syntactic and semantic components for correct type classification.

This formalization provides a foundation for reasoning about Perl code, building optional static analysis tools, and potentially developing gradual typing systems for Perl. The type relationships identified here reflect the actual structure implicit in Perl's runtime semantics, making the formalization both descriptively accurate and prescriptively useful for program verification and optimization.

## References

### Type Theory and Semantics

- **Abramsky, S.** (1990). "The Lazy Lambda Calculus." In *Research Topics in Functional Programming*, ed. D. Turner. Addison-Wesley.

- **Amadio, R. M. and Cardelli, L.** (1993). "Subtyping Recursive Types." *ACM Transactions on Programming Languages and Systems* 15(4): 575-631.

- **Cardelli, L.** (1988). "Structural Subtyping and the Notion of Power Type." In *Proceedings of POPL 1988*, 70-79.

- **Courcelle, B.** (1983). "Fundamental Properties of Infinite Trees." *Theoretical Computer Science* 25: 95-169.

- **Liskov, B. and Wing, J.** (1994). "A Behavioral Notion of Subtyping." *ACM Transactions on Programming Languages and Systems* 16(6): 1811-1841.

- **Morris, J. H.** (1968). "Lambda Calculus Models of Programming Languages." PhD thesis, MIT.

- **Scott, D. and Strachey, C.** (1971). "Toward a Mathematical Semantics for Computer Languages." In *Proceedings of the Symposium on Computers and Automata*, Polytechnic Institute of Brooklyn.

### Gradual and Soft Typing

- **Cartwright, R. and Fagan, M.** (1991). "Soft Typing." In *Proceedings of PLDI 1991*, 278-292.

- **Henglein, F. and Rehof, J.** (1995). "Safe Polymorphic Type Inference for a Dynamically Typed Language: Translating Scheme to ML." In *Proceedings of FPCA 1995*, 192-203.

- **Siek, J. and Taha, W.** (2006). "Gradual Typing for Functional Languages." In *Proceedings of the Scheme and Functional Programming Workshop*, 81-92.

- **Siek, J. and Taha, W.** (2007). "Gradual Typing for Objects." In *Proceedings of ECOOP 2007*, LNCS 4609, 2-27.

- **Tobin-Hochstadt, S. and Felleisen, M.** (2008). "The Design and Implementation of Typed Scheme." In *Proceedings of POPL 2008*, 395-406.

- **Tobin-Hochstadt, S. and Felleisen, M.** (2010). "Logical Types for Untyped Languages." In *Proceedings of ICFP 2010*, 117-128.

### Coercion and Type Systems

- **Henglein, F.** (1994). "Dynamic Typing: Syntax and Proof Theory." *Science of Computer Programming* 22(3): 197-230.

- **Bierman, G., Abadi, M., and Torgersen, M.** (2014). "Understanding TypeScript." In *Proceedings of ECOOP 2014*, LNCS 8586, 257-281.

### Contracts and Behavioral Types

- **Findler, R. B. and Felleisen, M.** (2002). "Contracts for Higher-Order Functions." In *Proceedings of ICFP 2002*, 48-59.

### Type Inference for Dynamic Languages

- **An, J.-H., Chaudhuri, A., and Foster, J. S.** (2011). "Static Typing for Ruby on Rails." In *Proceedings of ASE 2011*, 590-594.

### Language-Specific Type Systems

- **PEP 484** - Type Hints (Python). Python Enhancement Proposal 484, 2014. https://www.python.org/dev/peps/pep-0484/

### Standards and Documentation

- **IEEE Standard 754-2019.** *IEEE Standard for Floating-Point Arithmetic.* Institute of Electrical and Electronics Engineers, 2019.

- **Perl Documentation.** *perldata*, *perlop*, *perlsyn*. Official Perl language documentation. https://perldoc.perl.org/

### Perl Modules

- **Scalar::Util.** Core Perl module providing utility functions including `looks_like_number` (numeric type testing) and `dualvar` (creating values with independent string/numeric interpretations). https://metacpan.org/pod/Scalar::Util
