# The Runtime-Free Boundary: statically-knowable dispatch vs runtime-unknowable dispatch

**Date:** 2026-06-07 (revised — reframed around static-vs-dynamic dispatch per
perigrin)
**Status:** ANALYSIS / boundary map. The prerequisite knowledge that bounds the
gap-clearing campaign. Derived from `perl-type-system-formal.md`,
`typed-ir-representation.md`, the Chalk subset restrictions, and Perl 5.42
semantics.

## The governing principle

**Every Perl value type = a real machine-level representation + explicit `Coerce`
edges reproducing Perl's semantics at the boundaries.** (perigrin, 2026-06-07.)
The value's identity is the clean machine representation; the "Perl-ness" lives
in the coercion functions. So runtime-free is the DEFAULT: a value type is
lowerable without the interpreter iff we can pick a machine representation and
write its coercion functions, validated against perl (corpus, lli==perl).

## The actual boundary: compile-time-knowable vs runtime-unknowable DISPATCH

The earlier draft of this doc had a "needs libperl" bucket. **That was a false
category.** libperl was only ever needed as a proxy for "the compiler cannot
statically determine what runs." The real, single dividing line is:

> **Can the compiler statically know what code/operation runs?**
> - **YES → Runtime-Free (RF).** Lower it: a representation + a known function
>   (coercion), a known vtable slot (method / overload / tie handler), a known
>   matcher (regex literal → DFA), a known graph edge (`$1`, `$!`).
> - **NO → Out-Of-Subset (OOS).** The behavior is not determined until runtime
>   (string `eval` generates new code; runtime symbol-table / `@ISA` mutation
>   changes dispatch; `local`/dynamic-scope depends on the runtime call stack).
>   These cannot be compiled standalone OR faithfully — they are excluded.

There is **no "libperl-required" middle bucket.** libperl was the fallback you
reach for *because* you couldn't statically resolve dispatch — and if you can't
statically resolve it, it's runtime-unknowable, which is OOS. The two buckets are
RF and OOS.

### Why the runtime-free boundary ≈ the Chalk subset boundary

The Chalk subset was defined to exclude the dynamic / reflective features (string
eval, mutation through references, dynamic dispatch). Those are EXACTLY the
runtime-unknowable-dispatch features. The subset boundary and the RF boundary are
the same line drawn twice — not a coincidence, but the same underlying cut:
"exclude what isn't statically determined." This gives a clean, decidable test
for any future feature: *can the compiler statically know what runs?*

### The crucial nuance: knowability must extend to the dispatch TABLES

`overload` and `tie` are RF **because their dispatch tables are declared
statically** — `use overload '+' => \&f` at class-def time; `tie $x, 'KnownClass'`
with a literal class. Dispatch keyed by operator/access instead of name is still a
known vtable lookup. The line is crossed only when the *table or target* is a
runtime-computed value (`tie $x, $dynamic_class`, runtime `push @ISA`,
`*name = \&sub`). For `feature class` specifically this is clean: classes are
lexically declared, no runtime `@ISA` mutation in the subset → the vtable is fully
known at compile time.

## Bucket RF — statically-knowable dispatch (nearly everything; the campaign)

### Scalars (representation + coercion edges)
- **Bool** = `i1`. Coerce(Bool→Num)=0/1, Coerce(Bool→Str)="" /"1", Coerce(*→Bool)=
  truthiness, UnaryNot(Bool)→Bool. (Verified: a real bool, not a string; `is_bool`
  distinguishes it.) **RF.**
- **Int** = `i64`; coercions to Num(`sitofp`)/Str(decimal)/Bool(`!=0`); native
  arithmetic; Int-overflow→Coerce(Int→Num) (Phase-3 guard). **RF.**
- **Num** = `double`; coercions to Str(perl stringification)/Int(trunc)/Bool;
  IEEE arith. **RF.** (Num→Str exact formatting is a correctness sub-project.)
- **Str** = `{ptr, len}` machine buffer; concat = alloc+copy; Coerce(Str→Num)=
  perl leading-numeric rule (`"3abc"`→3, `"abc"`→0, ...), Coerce(Str→Bool)=
  `""||"0"→false`; length/substr/index pure. **RF.** (Str→Num is the canonical
  "subtle but specifiable, not magic" coercion.)
- **Undef** = niche/tag; coercions to 0/""/false (+ warnings). **RF.**
- **DualVar** = `{num, str}` pair (e.g. `$!`); coercions pick the face. **RF.**

### Aggregates
- **Array** = `{len, cap, elem*}` vector; push/pop/index/`scalar @a`/slice pure;
  Coerce(Array→List)=flatten. **RF.**
- **Hash** = hash table `{Str→value}`; keys/values/exists/delete/lookup pure;
  Coerce(Hash→List)=flatten. **RF.** (Iteration order is randomized in perl; the
  corpus normalizes hash order — RF lowering matches the normalized behavior.)
- **ArrayRef / HashRef** = pointer to the struct + ref tag; deref/element =
  load-through-pointer. **RF.** (Ref-address stringification `"ARRAY(0x..)"` is a
  determinism caveat — see open questions.)

### Control / dispatch / code
- **Control flow** (if/else/while/for/&&/||) = LLVM basic blocks + br + phi. **RF.**
  (&&/|| are short-circuit control flow — the SAME gap as if/while/for.)
- **Comparisons** = icmp/fcmp → Bool. **RF.**
- **CodeRef / named sub / closure** = function pointer + captured-env struct;
  call = indirect call. **RF.**
- **Method dispatch (feature class)** = static MOP → per-class vtable; call =
  vtable slot + indirect call. Object = `{class*, fields}` struct; field = offset;
  ADJUST = constructor code. **RF** (static MOP, no runtime mutation in subset).
- **`overload`** = a vtable keyed by OPERATOR. `Coerce(OverloadedObj→Str)` = call
  the class's `""` slot; `obj + x` = call the `+` slot. Just method dispatch with
  a different key. The table is declared statically. **RF** (was wrongly LP).
- **`tie`** = a vtable keyed by ACCESS (FETCH/STORE/...). A tied access = indirect
  call to the handler slot. Same static-dispatch mechanism. **RF** (was wrongly
  LP) — provided the tie class is a literal (runtime-computed class → OOS).

### "Magic" variables — per-variable; mostly graph-produced values or host state
- **`$1`..`$9`, `$&`, `$+{...}`** = OUTPUTS of a regex-match operation. A match
  node produces `(matched?, $1, $2, ...)`; reading `$1` = reading a slot of the
  match node's result — a value on a graph edge. **RF** (graph-produced, not
  ambient interpreter state).
- **`$!`** = errno (Num face = syscall return) + strerror (Str face). Both are
  values the failing-syscall operation escapes into the graph; a DualVar rep.
  **RF.**
- **`%ENV`, `@ARGV`** = host process state, read via plain C (`getenv`/`environ`,
  `argv`); writes via `setenv`. Host-interface layer, NOT libperl. **RF.**
- **I/O config (`$/`, `$\`, `$,`)** = consumed by I/O nodes. RF if modelled as
  values the I/O ops read; if treated as `local`-dynamic globals, that's the
  dynamic-scope OOS question (see below). (Open edge — decide when I/O is tackled.)

### Regex — an RF SUB-COMPILER (not libperl) — BUILT 2026-06-10 (G6)
Perl's regex is large, but it is NOT interpreter-coupled in the dispatch sense: a
literal pattern is a compile-time-known mini-language. The RF answer is a
**regex sub-compiler** (pattern → DFA/NFA/bytecode matcher), emitted runtime-free
— "an entire separate compiler and mini-language" (perigrin), a bounded
sub-project, NOT a libperl dependency. The genuinely-OOS regex feature is
`(?{ perl code })` (embedded runtime code) and arguably the full
Unicode-property surface — those are runtime-unknowable. Core patterns are RF.

**Regex is validatable BEFORE the parser exists** (perigrin, 2026-06-07). The
parser, when built, will emit *the same IR* for a regex match that we can
hand-author today: `%m = RegexMatch(%subject, /pattern/) -> (matched?, $1, $2)`.
The constructive corpus (the markdown IS the graph) lets us write that match IR
by hand, lower it through the regex sub-compiler to a matcher, and tie out
`lli == perl` with NO parser in the loop. This *decouples* matcher-correctness
from parser-existence: we build and verify the matcher now, and the hand-authored
IR shape becomes the contract the parser is later checked against. Regex is thus
the cleanest case for the corpus's constructive design — the one capability where
the IR producer does not yet exist, so the hand-authored graph stands in for it
entirely. Not "deferred until the parser catches up": validatable today, with the
IR shape pinned as the parser's future spec.

## Bucket OOS — runtime-unknowable dispatch (excluded; never lowered)

The behavior is not determined until runtime, so it cannot be compiled standalone
or faithfully. These are also (not coincidentally) the features the Chalk subset
already excludes:
- **String `eval "..."`** — generates new code at runtime. Already excluded.
- **Runtime symbol-table mutation / typeglobs** (`*foo = \&bar`) — changes
  dispatch at runtime.
- **Runtime `@ISA` / MOP mutation** (`push @ISA`, runtime `add_method`) — changes
  the vtable after compile. (The subset's `feature class` forbids this → vtable
  stays static → RF.)
- **`local` on globals / dynamic scope** — what's visible depends on the runtime
  call stack.
- **Mutation through references** (`$$ref = ...`) — already excluded (SSA aliases).
- **`tie`/`overload` with a runtime-computed class or handler** — table unknowable.
- **`(?{ perl code })` in regex** — runtime code inside the matcher.

## The boundary, summarized

| Capability | Bucket | Why |
|---|---|---|
| Bool/Int/Num/Str/Undef/DualVar + coercions | RF | rep + known coercion functions |
| Array/Hash/refs | RF | data structures; known ops |
| control flow, comparisons, &&/|| | RF | known branch/phi structure |
| CodeRef / closures | RF | fn-ptr + captured-env |
| feature-class method dispatch | RF | static vtable (known class) |
| **overload** | **RF** | vtable keyed by operator (declared table) |
| **tie** (literal class) | **RF** | vtable keyed by access (declared table) |
| **`$1`, `$!`** | **RF** | graph-produced values, not ambient state |
| **`%ENV`, `@ARGV`** | **RF** | host C interface (getenv/argv), not libperl |
| **regex (core patterns)** | **RF** | a deferred regex SUB-COMPILER (DFA), not libperl |
| string eval | OOS | generates code at runtime |
| symbol-table / typeglob / runtime @ISA mutation | OOS | dispatch changes at runtime |
| local / dynamic scope, ref-mutation | OOS | runtime-call-stack / SSA-excluded |
| tie/overload w/ runtime-computed class | OOS | dispatch table unknowable |
| `(?{ code })`, string eval in regex | OOS | runtime code in the matcher |

**There is no libperl-required bucket.** Everything is RF (statically-knowable
dispatch) or OOS (runtime-unknowable dispatch).

## What this means for the campaign

- **The runtime-free reach is essentially the entire subset.** Strings, arrays,
  hashes, the feature-class object model, control flow, closures, overload, tie,
  regex-captures, `$!`, `%ENV` — all RF. A standalone Perl compiler for the Chalk
  subset needs NO libperl fallback: it needs value reps + coercions, static
  vtable dispatch (subsuming overload+tie), a regex sub-compiler, and a host-C
  interface layer.
- **The self-host target is reachable in principle.** The biggest GAP cluster
  (MOP/object) is RF (static vtables + structs). Self-hosting Chalk's own
  `feature class` code through a standalone compiler is not blocked on libperl.
- **The corpus drives it**: each RF capability = "implement representation X +
  Coerce(X→*) (or the vtable/matcher), validate vs perl (lli==perl)." Bounded,
  testable, idiom-by-idiom.
- **The hand-authored IR is also the parser's spec.** Because the corpus's
  ir-blocks are constructive (the markdown IS the graph), every validated case
  pins the exact IR shape the future parser must emit for that idiom. The
  validation is "this graph lowers to perl's behavior"; the by-product is "this
  is the graph the parser owes us." This is load-bearing for any capability whose
  IR producer does not yet exist — regex most of all (the parser does not emit
  `RegexMatch` today), but it holds for the whole corpus: we are building the
  IR-contract the parser will be checked against, not waiting for the parser to
  define it. The producer is hand-authored now; the parser replaces the hand
  later, against a contract already proven correct.

### Campaign sequence (leverage × cleanliness)

> **STATUS 2026-06-10: items 1–7 are DONE** (G1–G7 closed in git-zhi,
> milestone codegen-harness). 1–5 landed in the G2–G5 campaign (the MOP
> lowering since converged onto ClassInfo + Call by the R1–R3 taxonomy
> reconciliation). 6 (the regex sub-compiler) was BUILT in G6 — Option-B
> core: literals, anchors (incl. `$`-before-final-newline), classes, byte
> escapes, greedy quantifiers with backoff backtracking, capture groups,
> qr// (`Constant(const_type='regex')` + `Match`), s/// splice; alternation/
> `\Q\E`/`\G`/`/g`/non-greedy/backrefs/`!~`/flags die as explicit GAPs
> (issue 019eb073). 7 landed its census-grounded core in G7: `RegexCapture`
> ($N) + `EnvRead` (%ENV); @ARGV/$0/$!/I-O-config/env-writes/undef-faces
> deferred (issue 019eb0d7 — zero lib/ uses). overload/tie remain G5b.
> The hand-authored-IR-as-parser-spec framing remains accurate and
> load-bearing.

1. **cfg-blocks-phi** (control + &&/||) — RF, highest leverage, no value reps.
2. **Bool repr + Coerce(Bool→*)** — RF, small, closes `!` + bare-bool.
3. **Str** (buffer + coercions) — RF, the canonical coercion project, reused widely.
4. **Array / Hash** — RF containers, bigger but mechanical.
5. **feature-class MOP** (vtables/structs) — RF, largest, the self-host target.
   (overload/tie ride on this once vtable dispatch exists.)
6. **regex sub-compiler** — the one self-contained mini-compiler.
7. **host interface** (`%ENV`/`@ARGV`/I/O), magic-var graph edges (`$1`/`$!`) —
   RF plumbing, done alongside the features that produce/consume them.

## Open questions
1. **Determinism caveats:** ref-address stringification (`"ARRAY(0x..)"`) and
   hash iteration order are non-deterministic in perl; the corpus normalizes
   them — confirm the normalization policy covers ref-address stringification.
2. **I/O config vars (`$/`, `$\`):** modelled as values consumed by I/O nodes
   (RF) vs `local`-dynamic globals (OOS) — decide when I/O is tackled.
3. **Num→Str exact formatting:** validate the RF formatter against perl across
   edge cases (very large/small, negative zero, `%.15g` quirks).
4. **Regex scope:** the DFA-compilable core vs the OOS tail (`(?{})`, exotic
   Unicode) — draw the line when the regex sub-compiler is built.
5. **overload/tie:** confirm the subset requires a literal (statically-known)
   class/handler so the dispatch table is compile-time-knowable.
