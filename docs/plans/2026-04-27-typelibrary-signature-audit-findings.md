# TypeLibrary Signature Audit Findings

**Date:** 2026-04-27
**Auditor:** subagent (Opus 4.7)
**Subject:** `lib/Chalk/Grammar/Perl/TypeLibrary.pm` — `%BUILTIN_SIGNATURES`
**Branch:** `worktree-pu`
**Oracle:** `perldoc -f BUILTIN` (Perl 5.42.0 as installed via pvm)
**Scope:** Read-only audit; no production code modified. The XS, MOP, and
DepChaser surfaces are out of scope. This audit produces a punch list and
vocabulary-gap inventory only.

## Summary

- Signatures audited: **28** (entries in `%BUILTIN_SIGNATURES`)
- Correct: **6**
- Too strict (Bug 6 class — blocks legitimate Perl): **5**
- Too lax (silently accepts invalid Perl): **6**
- Wrong type (uses a TypeLibrary type that misrepresents perldoc semantics): **8**
- Missing variant (perldoc lists multiple call shapes; TypeLibrary encodes one): **9**
- Unverifiable / context-dependent: **2**

(The category counts overlap: many signatures suffer from more than one defect,
so the totals exceed 28. Each builtin's primary verdict is recorded under its
section.)

The dominant pattern in TypeLibrary is **first-position rigor with variadic-tail
laxity**: the first argument is typed precisely (and is sometimes wrong), while
later positions collapse to `Any`. There is no consistent rationale visible in
the file. The ad-hoc framing in the prompt is supported by the audit: the
signatures were authored case-by-case rather than from a single principled
translation of Perl semantics.

## Per-builtin findings

Every "should accept X" claim below cites a specific perldoc sentence. Where
the sentence is broad enough that no quote nails it, the citation calls that
out.

---

### `push`

**Current TypeLibrary signature:** `arg_types => ['Array', 'Any'], min_arity => 2, return_type => 'Int'`

**perldoc -f push:**
> push ARRAY,LIST
> Adds one or more items to the end of an array. […] Returns the number of elements in the array following the completed "push".
> Starting with Perl 5.14, an experimental feature allowed "push" to take a scalar expression. This experiment has been deemed unsuccessful, and was removed as of Perl 5.24.

**Verdict:** **Correct (with one caveat: too lax on first arg)**.

**Specific issues:**
- First arg: documented as `ARRAY` exclusively — the `push EXPR, LIST`
  experiment was removed in 5.24. TypeLibrary's `Array` is correct.
  No defect here.
- LIST: `Any` is the right choice given Perl's flattening (any scalar/array/hash
  flattens). Modeling LIST as `Any` is semantically correct.
- Return type `Int`: matches perldoc ("the number of elements"). Correct.
- Caveat: there is no enforcement that the first arg's static type is
  *literally* `Array` rather than `ArrayRef`. Passing `ArrayRef` would
  segfault or fail at runtime, but the type system would not catch it. This
  is a "too lax" possibility but only via syntactic accident — at the parse
  layer, the grammar already restricts the first arg to `@…` or
  array-deref expressions. Probably a non-issue in practice.

**Site count in lib/:** 3 parens, 48 bare. Bug 5 affects parens form (4
sites including `unshift`/`join`/`substr`).

**Suggested fix:** None (signature itself is correct).

**Side effects:** The Bug 5 RCA is unrelated to this signature — that's a
walker bug in TypeInference, not a signature defect.

---

### `pop`

**Current TypeLibrary signature:** `arg_types => ['Array'], min_arity => 1, return_type => 'Scalar'`

**perldoc -f pop:**
> pop ARRAY
> pop
> Removes and returns the last element of the array, shortening the array by one element. […] Returns "undef" if the array is empty.
> If ARRAY is omitted, "pop" operates on the @ARGV array in the main program, but the @_ array in subroutines.

**Verdict:** **Wrong arity (min_arity should be 0) + Missing variant**.

**Specific issues:**
- `min_arity => 1` rejects bare `pop;` (which defaults to `@ARGV`/`@_`).
  perldoc explicitly documents `pop` with no argument.
- Return type `Scalar` is permissive; the actual returned type is whatever
  the array element holds, which TypeLibrary cannot express without
  parameterized types. `Scalar` is acceptable.
- Missing variant: no representation of "pop with no arg → context-dependent
  default array".

**Site count in lib/:** 1 parens, 3 bare.

**Suggested fix:** `min_arity => 0`. That single change retires the variant
gap and matches perldoc.

**Side effects:** Almost no real-world impact — Chalk-the-compiler doesn't
use bare `pop`. But the `pop`/`shift` divergence below shows the same defect
class.

---

### `shift`

**Current TypeLibrary signature:** `arg_types => ['Array'], min_arity => 1, return_type => 'Scalar'`

**perldoc -f shift:**
> shift ARRAY
> shift
> Removes and returns the first element of an array. […] If ARRAY is omitted, "shift" operates on the @ARGV array in the main program, and the @_ array in subroutines.

**Verdict:** **Wrong arity (min_arity should be 0) + Missing variant**.

**Specific issues:** Same as `pop`. Bare `shift;` is canonical inside method
bodies with old-style `@_` argument unpacking, though uncommon in modern
class-based code.

**Site count in lib/:** 1 parens, 6 bare. Bare is much more common.

**Suggested fix:** `min_arity => 0`.

**Side effects:** Modern Perl 5.42 class syntax with method signatures makes
bare `shift` a rare construct, but it remains valid Perl.

---

### `unshift`

**Current TypeLibrary signature:** `arg_types => ['Array', 'Any'], min_arity => 2, return_type => 'Int'`

**perldoc -f unshift:**
> unshift ARRAY,LIST
> Add one or more elements to the beginning of an array.
> Returns the new number of elements in the updated array.

**Verdict:** **Correct.**

**Specific issues:** None. Same shape as `push`.

**Site count in lib/:** 0 parens, 2 bare. (Probe-set member of Bug 5 — the
parens form is rejected by the walker bug, not by this signature.)

**Suggested fix:** None.

---

### `splice`

**Current TypeLibrary signature:** `arg_types => ['Array', 'Num', 'Num', 'Any'], min_arity => 1, return_type => 'List'`

**perldoc -f splice:**
> splice ARRAY,OFFSET,LENGTH,LIST
> splice ARRAY,OFFSET,LENGTH
> splice ARRAY,OFFSET
> splice ARRAY
> Removes the elements designated by OFFSET and LENGTH from an array, and replaces them with the elements of LIST, if any. In list context, returns the elements removed from the array. In scalar context, returns the last element removed, or "undef" if no elements are removed.
> If OFFSET is negative then it starts that far from the end of the array. […] If LENGTH is negative, removes the elements from OFFSET onward except for -LENGTH elements at the end of the array.

**Verdict:** **Wrong type + Unverifiable return**.

**Specific issues:**
- OFFSET (position 1): typed as `Num`, but perldoc treats it as an integer
  (no fractional offsets accepted). Should be `Int`.
- LENGTH (position 2): same — typed as `Num`, should be `Int`. Negative
  values are explicitly supported, so the type is `Int`, not `PositiveInt`.
- Return type: TypeLibrary says `List`, but perldoc says "in list context,
  returns […]; in scalar context, returns the last element removed […]".
  The return type is genuinely context-dependent. `List` over-commits to
  one context. Without a context-typed return-type representation,
  `List` is the more useful default for the common (list-context) case,
  but the signature is silently incorrect for scalar context.

**Site count in lib/:** 0 parens, 1 bare.

**Suggested fix:** `arg_types => ['Array', 'Int', 'Int', 'Any']`. Return-type
ambiguity is an architectural gap (see Vocabulary Gap 4 below) — leave
`List` for now.

**Side effects:** Splice is rare in lib/ (1 site). Low priority.

---

### `keys`

**Current TypeLibrary signature:** `arg_types => ['Hash'], min_arity => 1, return_type => 'List'`

**perldoc -f keys:**
> keys HASH
> keys ARRAY
> Called in list context, returns a list consisting of all the keys of the named hash, or in Perl 5.12 or later, the indices of an array. […] In scalar context, returns the number of keys or indices.

**Verdict:** **Too strict (Bug 6 class) + Wrong return**.

**Specific issues:**
- First arg: TypeLibrary requires `Hash` but perldoc explicitly accepts
  `HASH` *or* `ARRAY` (since 5.12). Passing an array (e.g.,
  `keys @arr` to get indices) is rejected. This rejects valid Perl.
- Hashref/arrayref: in modern Perl, `keys $hashref->%*` and
  `keys $arrayref->@*` work via dereference; the dereferenced result is
  what `keys` operates on, so the signature itself doesn't need to know
  about `HashRef`/`ArrayRef`. The dereference happens before this check.
  Still, "auto-deref" `keys %{$href}` is the older idiom and the
  experimental autoderef ran 5.14-5.22 (removed); not a current concern.
- Return type: `List` in list context, `Int` in scalar context. TypeLibrary
  picks `List`. Same context-dependence issue as `splice`.

**Site count in lib/:** 6 parens, 45 bare. **High site count.**

**Suggested fix:** `arg_types => ['List']` or introduce a `Hash|Array` union
(see Vocabulary Gap 1). Using `List` covers both Hash and Array (both are
subtypes of `List` in the hierarchy at lines 30-32) — a single-word fix
that admits both shapes.

Verification of subtyping: `Hash => 'List'` and `Array => 'List'` per
TypeLibrary lines 31-32. So `type_satisfies('Hash', 'List')` and
`type_satisfies('Array', 'List')` both return true via the `is_subtype`
branch. **`List` is the correct positional type.**

**Side effects:** Fixing this also fixes `values` and `each` (same defect).
Unblocks `keys @arr` patterns in lib/ — survey would identify 0 such sites
today (Chalk doesn't use this idiom), but the signature is incorrect on
principle.

**Per perldoc Perl 5.12 timeline note**: the Perl 5.42 oracle confirms
`keys ARRAY` is current, not deprecated.

---

### `values`

**Current TypeLibrary signature:** `arg_types => ['Hash'], min_arity => 1, return_type => 'List'`

**perldoc -f values:**
> values HASH
> values ARRAY
> Called in list context, returns a list consisting of all the value of the named hash, or in Perl 5.12 or later, the values of an array.

**Verdict:** **Too strict (Bug 6 class) + Wrong return.**

**Specific issues:** Same as `keys` — accepts `HASH` or `ARRAY` per perldoc.
Same context-dependent return as `keys`/`splice`.

**Site count in lib/:** 4 parens, 35 bare.

**Suggested fix:** `arg_types => ['List']`. Bundle with `keys`/`each` fix.

---

### `delete`

**Current TypeLibrary signature:** `arg_types => ['Scalar'], min_arity => 1, return_type => 'Scalar'`

**perldoc -f delete:**
> delete EXPR
> Given an expression that specifies an element or slice of a hash, "delete" deletes the specified elements from that hash so that "exists" on that element no longer returns true.
> "delete" may also be used on arrays and array slices, but its behavior is less straightforward.
> In list context, usually returns the value or values deleted, or the last such element in scalar context.

**Verdict:** **Too strict + Wrong return.**

**Specific issues:**
- First arg: typed as `Scalar`, but perldoc says `EXPR`. The expression must
  resolve to a hash element, hash slice, array element, or array slice.
  Slices are *list*-typed in TypeLibrary terms (`@hash{@keys}` is List).
  Rejecting list slices means rejecting `delete @hash{@keys}` (a 5.x idiom).
- Return: list context returns a list; scalar context returns the last.
  Same context dependence.

**Site count in lib/:** 1 parens, 20 bare.

**Suggested fix:** `arg_types => ['Any']` (the lvalue check at the grammar
layer enforces the structural constraint that `Scalar` was approximating).
Or, more precisely, `arg_types => ['List']` if list-flattening is desired
(slice case).

**Side effects:** Unblocks `delete @hash{@keys}` patterns. Whether lib/ has
such patterns is open — most `delete` use is `delete $h{k}`, where the type
is Scalar. The signature is imprecise but not commonly hit.

---

### `exists`

**Current TypeLibrary signature:** `arg_types => ['Scalar'], min_arity => 1, return_type => 'Bool'`

**perldoc -f exists:**
> exists EXPR
> Given an expression that specifies an element of a hash, returns true if the specified element in the hash has ever been initialized, even if the corresponding value is undefined.

**Verdict:** **Correct on first-arg structure; arguably too strict on slice form** (perldoc doesn't document slice `exists` because slices use a different mechanism, but `exists $hash{$k}` is an Lvalue form whose static type is Scalar).

**Specific issues:**
- First arg: `Scalar` matches the dominant use (`exists $h{k}`). Perl does
  not have a slice form of `exists` (unlike `delete`).
- Return: `Bool` matches perldoc.

**Site count in lib/:** 4 parens, 117 bare. **Very high site count** —
the most-called of any audited builtin.

**Suggested fix:** None (correct).

**Side effects:** None.

---

### `each`

**Current TypeLibrary signature:** `arg_types => ['Hash'], min_arity => 1, return_type => 'List'`

**perldoc -f each:**
> each HASH
> each ARRAY
> When called on a hash in list context, returns a 2-element list consisting of the key and value for the next element of a hash. When called in scalar context, returns only the key (not the value).
> When called on an array in list context, in Perl 5.12 and later, it returns a 2-element list consisting of the index and value for the next element of the array.

**Verdict:** **Too strict + Wrong return.**

**Specific issues:** Same as `keys`/`values`.

**Site count in lib/:** 0 parens, 60 bare.

**Suggested fix:** `arg_types => ['List']`. Bundle with `keys`/`values`.

---

### `length`

**Current TypeLibrary signature:** `arg_types => ['Str'], min_arity => 0, return_type => 'Int'`

**perldoc -f length:**
> length EXPR
> length
> Returns the length in characters of the value of EXPR. If EXPR is omitted, returns the length of $_. If EXPR is undefined, returns "undef".

**Verdict:** **Correct (mostly) — return type slightly off.**

**Specific issues:**
- First arg: `Str` is correct (Perl coerces any scalar to string).
- `min_arity => 0` correctly admits bare `length;`.
- Return type: perldoc says "returns "undef"" for undefined input. TypeLibrary's
  `Int` doesn't admit `Undef`. The composition `Int|Undef` would be more
  accurate, but `Int` is the dominant case. This is a "too lax" issue:
  downstream consumers may not handle the undef case.
- Strictly, length returns 0 or larger non-negative integer — `PositiveInt` or
  `Nat` would be more precise. Refinement type gap.

**Site count in lib/:** 23 parens, 14 bare.

**Suggested fix:** None (the current type is close enough). Document the
`undef` edge case in a refinement-types pass (Vocabulary Gap 3).

**Side effects:** None.

---

### `chomp`

**Current TypeLibrary signature:** `arg_types => ['Any'], min_arity => 0, return_type => 'Int'`

**perldoc -f chomp:**
> chomp VARIABLE
> chomp( LIST )
> chomp
> This safer version of "chop" removes any trailing string that corresponds to the current value of $/. […] It returns the total number of characters removed from all its arguments. […] If VARIABLE is omitted, it chomps $_.

**Verdict:** **Too lax + Missing variant.**

**Specific issues:**
- First arg: typed as `Any`, but perldoc says `VARIABLE` or `LIST`. Specifically
  this means an *lvalue* — `chomp("foo")` is a syntax error (must be an
  lvalue). `Any` admits any expression.
- The operand mutation is invisible to the type system (chomp modifies its
  argument in place).
- Missing variant: `chomp(LIST)` exists; the signature flattens to a single
  Any. With `Any` typing this works coincidentally.

**Site count in lib/:** 0 parens, 2 bare. Very rare.

**Suggested fix:** None urgent. The lvalue requirement should be enforced at
grammar layer if at all; type-level enforcement requires an `Lvalue` type
that doesn't currently exist.

**Side effects:** Negligible.

---

### `chop`

**Current TypeLibrary signature:** `arg_types => ['Any'], min_arity => 0, return_type => 'Str'`

**perldoc -f chop:**
> chop VARIABLE
> chop( LIST )
> chop
> Chops off the last character of a string and returns the character chopped.
> If you chop a list, each element is chopped. Only the value of the last "chop" is returned.

**Verdict:** **Too lax** (same lvalue concern as `chomp`).

**Specific issues:** Identical to `chomp`. Return type: `chop` returns the
character chopped (a single-character string), not an `Int` like `chomp`.
TypeLibrary's `Str` is correct.

**Site count in lib/:** 0 parens, 1 bare. Essentially unused; modern Perl
prefers `chomp`.

**Suggested fix:** None urgent.

---

### `chr`

**Current TypeLibrary signature:** `arg_types => ['Int'], min_arity => 1, return_type => 'Str'`

**perldoc -f chr:**
> chr NUMBER
> chr
> Returns the character represented by that NUMBER in the character set. […] If NUMBER is omitted, uses $_.

**Verdict:** **Wrong arity (min_arity should be 0) + Wrong type (NUMBER, not Int).**

**Specific issues:**
- `min_arity => 1` rejects bare `chr;` (defaults to `$_`).
- Argument: perldoc says NUMBER. Whether that means Int or Num is
  ambiguous — `chr(65.7)` truncates to integer behavior in practice
  ("truncated to an integer"). `Int` is the spirit but Perl accepts
  Num and truncates. The signature is too strict if the caller passes
  a Num.

**Site count in lib/:** 0 parens, 2 bare. Rare.

**Suggested fix:** `min_arity => 0`. Optionally widen `Int` to `Num`. The
Num→Int truncation is documented Perl behavior; rejecting it would be
overly strict.

---

### `ord`

**Current TypeLibrary signature:** `arg_types => ['Str'], min_arity => 0, return_type => 'Int'`

**perldoc -f ord:**
> ord EXPR
> ord
> Returns the code point of the first character of EXPR. If EXPR is an empty string, returns 0. If EXPR is omitted, uses $_.

**Verdict:** **Correct.**

**Specific issues:** None.

**Site count in lib/:** 3 parens, 2 bare.

**Suggested fix:** None.

---

### `join`

**Current TypeLibrary signature:** `arg_types => ['Str', 'Any'], min_arity => 2, return_type => 'Str'`

**perldoc -f join:**
> join EXPR,LIST
> Joins the separate strings of LIST into a single string with fields separated by the value of EXPR, and returns that new string.
> Beware that unlike "split", "join" doesn't take a pattern as its first argument. Compare "split".

**Verdict:** **Correct.**

**Specific issues:**
- First arg: `Str` matches perldoc (a string separator, not a regex — perldoc
  is explicit: "doesn't take a pattern").
- LIST: `Any` accepts everything; correct via flattening.
- min_arity 2: matches perldoc — both EXPR and LIST are required for the
  documented form.
- Return type `Str`: matches.

**Site count in lib/:** 131 parens, 3 bare. **Very high site count for parens
form** — and Bug 5 affects parens specifically.

**Suggested fix:** None (signature correct). Bug 5 is a TypeInference walker
issue independent of this signature.

---

### `split` ★ (Bug 6 anchor)

**Current TypeLibrary signature:** `arg_types => ['Regex', 'Str', 'Num'], min_arity => 1, return_type => 'List'`

**perldoc -f split:**
> split /PATTERN/,EXPR,LIMIT
> split /PATTERN/,EXPR
> split /PATTERN/
> split
> Splits the string EXPR into a list of strings and returns the list in list context, or the size of the list in scalar context.
> If only PATTERN is given, EXPR defaults to $_.
> The PATTERN need not be constant; an expression may be used to specify a pattern that varies at runtime.
> When PATTERN is the string " ", […] split emulates the default behavior of the command line tool awk.

**Verdict:** **Too strict (first arg) + Wrong type (third arg) + Missing variant.**

This is the **Bug 6 anchor case**. The audit was triggered by this entry.

**Specific issues:**
- First arg (PATTERN): typed as `Regex`. perldoc explicitly documents that
  PATTERN can be the string `" "` (special-cased awk emulation), and
  more generally that PATTERN "need not be constant; an expression may be
  used". Perl coerces strings to regexes here. **Should accept `Regex|Str`.**
- Second arg (EXPR): `Str` is correct.
- Third arg (LIMIT): typed as `Num`. perldoc consistently calls this an
  integer ("LIMIT value 1 means …"; "If LIMIT is negative…"). `Int` matches
  Perl semantics; `Num` accepts fractional limits which Perl truncates.
  Should be `Int`.
- Missing variant: `split` is documented with arities 0, 1, 2, 3 — TypeLibrary
  correctly says `min_arity => 1` (PATTERN-only and bare are
  documented), but the bare-form behavior (no args, defaults PATTERN to
  `" "` and EXPR to `$_`) is encoded only by the `min_arity` value, not
  by structural variant tracking. With `min_arity => 1`, bare `split;`
  is rejected. perldoc documents bare `split` (no args).
- Return type: list context returns a list, scalar context returns the count.
  Context dependence — same issue as `splice`/`keys`. `List` over-commits to
  the common case.

**Site count in lib/:** 2 parens, 21 bare.

**Suggested fix:**
1. First arg → `Regex|Str` (requires Vocabulary Gap 1 fix: union types).
2. Third arg → `Int`.
3. `min_arity => 0` to admit bare `split`.

If union types aren't yet available, the pragmatic interim is `arg_types => ['Any', 'Str', 'Int']` — under-typing is preferable to over-rejecting valid code.

**Side effects:** This is the highest-priority fix in the audit. Splits
that pass a string literal (`split(",", $s)`) currently reject. The lib/
site count of 2 parens + 21 bare suggests Chalk itself uses `split` mostly
in safe forms (likely with `qr/.../`-style patterns), but external
self-hosted Perl code commonly uses string-form `split`. Bug 6 was caught
because Chalk's grammar conformance test broke; the same defect blocks
arbitrary user code.

---

### `sprintf`

**Current TypeLibrary signature:** `arg_types => ['Str', 'Any'], min_arity => 1, return_type => 'Str'`

**perldoc -f sprintf:**
> sprintf FORMAT, LIST
> Returns a string formatted by the usual "printf" conventions of the C library function "sprintf".

**Verdict:** **Correct.**

**Specific issues:**
- First arg: `Str` (FORMAT) — correct.
- LIST: `Any` — correct via flattening.
- `min_arity => 1`: correct (FORMAT is required, LIST may be empty).
- Return: `Str` — correct.

**Site count in lib/:** 10 parens, 1 bare.

**Suggested fix:** None.

---

### `substr`

**Current TypeLibrary signature:** `arg_types => ['Str', 'Num', 'Num'], min_arity => 2, return_type => 'Str'`

**perldoc -f substr:**
> substr EXPR,OFFSET,LENGTH,REPLACEMENT
> substr EXPR,OFFSET,LENGTH
> substr EXPR,OFFSET
> Extracts a substring out of EXPR and returns it. First character is at offset zero. If OFFSET is negative, starts that far back from the end of the string. If LENGTH is omitted, returns everything through the end of the string.

**Verdict:** **Wrong type + Missing variant.**

**Specific issues:**
- First arg `Str`: correct.
- Second arg `Num` (OFFSET): perldoc treats OFFSET as integer. Should be `Int`.
- Third arg `Num` (LENGTH): perldoc treats LENGTH as integer. Should be `Int`.
- Missing variant: REPLACEMENT (4th arg) is documented but not in TypeLibrary.
  `substr($s, $i, $n, "REPLACEMENT")` is a documented form. With variadic
  fall-through (`$arg_types[-1]` semantics in `_complete_type`), the 4th
  position would currently be checked against `Num` (the last entry in
  arg_types), rejecting any string REPLACEMENT. Confirmed by reading
  `TypeInference.pm:373-374`:
  ```perl
  my $expected = $arg_types->[$sig_idx];
  $expected = $arg_types->[-1] if !defined $expected;
  ```
  So `substr($s, 0, 3, "REPLACEMENT")` would check position 3 against
  `Num`, reject "REPLACEMENT" as not a Num, and fail.

**Site count in lib/:** 23 parens, 1 bare.

**Suggested fix:** `arg_types => ['Str', 'Int', 'Int', 'Str']`. Or, since
the 4-arg form is rare and any-typed once you accept it, drop to
`['Str', 'Int', 'Int', 'Any']`.

**Side effects:** REPLACEMENT-form `substr` is uncommon in modern Perl.
Low site impact, but the Bug 6 class includes "Wrong type" — Num→Int matters.

---

### `defined`

**Current TypeLibrary signature:** `arg_types => ['Scalar'], min_arity => 1, return_type => 'Bool'`

**perldoc -f defined:**
> defined EXPR
> defined
> Returns a Boolean value telling whether EXPR has a value other than the undefined value "undef". If EXPR is not present, $_ is checked.

**Verdict:** **Wrong arity (min_arity should be 0) + Too strict on arg.**

**Specific issues:**
- min_arity 1: rejects bare `defined;` (defaults to `$_`).
- First arg: `Scalar` is the typical case but perldoc says EXPR. `defined &foo`
  (subroutine name) is documented and not strictly Scalar — it's a glob/sub
  name. Currently rejected.
- Return: `Bool` correct.

**Site count in lib/:** 36 parens, 804 bare. **Highest site count of any
builtin** — and the bare count is inflated by `return defined …` and
similar tail patterns that ag matches.

**Suggested fix:** `min_arity => 0`. Widening `Scalar` is debatable;
`defined &foo` is the only explicit edge.

---

### `ref`

**Current TypeLibrary signature:** `arg_types => ['Scalar'], min_arity => 1, return_type => 'Str'`

**perldoc -f ref:**
> ref EXPR
> ref
> Examines the value of EXPR, expecting it to be a reference, and returns a string giving information about the reference and the type of referent. If EXPR is not specified, $_ will be used.

**Verdict:** **Wrong arity (min_arity should be 0).**

**Specific issues:**
- min_arity 1: rejects bare `ref;` (defaults to `$_`).
- First arg: `Scalar` is correct (Perl coerces).
- Return: `Str` correct (perldoc: "returns a string").

**Site count in lib/:** 205 parens, 16 bare.

**Suggested fix:** `min_arity => 0`.

---

### `scalar`

**Current TypeLibrary signature:** `arg_types => ['Any'], min_arity => 1, return_type => 'Scalar'`

**perldoc -f scalar:**
> scalar EXPR
> Forces EXPR to be interpreted in scalar context and returns the value of EXPR.

**Verdict:** **Correct.**

**Specific issues:** None. Return is `Scalar` (correctly polymorphic).

**Site count in lib/:** 29 parens, 36 bare.

**Suggested fix:** None.

---

### `die`

**Current TypeLibrary signature:** `arg_types => ['Any'], min_arity => 0, return_type => 'None'`

**perldoc -f die:**
> die LIST
> "die" raises an exception. Inside an "eval" the exception is stuffed into $@ and the "eval" is terminated with the undefined value.

**Verdict:** **Correct.**

**Specific issues:**
- LIST: `Any` correct via flattening.
- min_arity 0: correct (`die;` re-raises `$@`).
- Return type `None`: correct (`die` doesn't return — `None` is bottom in
  TypeLibrary's hierarchy).

**Site count in lib/:** 0 parens, 62 bare.

**Suggested fix:** None.

---

### `warn`

**Current TypeLibrary signature:** `arg_types => ['Any'], min_arity => 0, return_type => 'Bool'`

**perldoc -f warn:**
> warn LIST
> Emits a warning, usually by printing it to "STDERR".

**Verdict:** **Wrong return type.**

**Specific issues:**
- Return type: TypeLibrary says `Bool`. perldoc doesn't explicitly document
  `warn`'s return value — but `warn` returns `1` (true) on success in
  practice. `Bool` is plausibly correct in spirit. Empirically `warn`
  returns 1 when no `__WARN__` handler intervenes, undef if a handler
  returns false. The actual behavior is implementation-defined; perldoc
  doesn't clarify. Mark as "unverifiable."
- Other fields: correct.

**Site count in lib/:** 1 parens, 17 bare.

**Suggested fix:** None — `Bool` is acceptable.

---

### `bless`

**Current TypeLibrary signature:** `arg_types => ['Ref', 'Str'], min_arity => 1, return_type => 'Object'`

**perldoc -f bless:**
> bless REF,CLASSNAME
> bless REF
> "bless" tells Perl to mark the item referred to by "REF" as an object in a package. The two-argument version of "bless" is always preferable unless there is a specific reason to *not* use it.

**Verdict:** **Correct.**

**Specific issues:**
- First arg: `Ref` correct.
- Second arg: `Str` (CLASSNAME) correct.
- min_arity 1: correctly admits both 1-arg and 2-arg forms.
- Return: `Object` — perldoc says it returns the first argument (a reference),
  but post-bless that reference *is* an object. `Object` matches the
  semantic outcome.

**Site count in lib/:** 0 parens, 1 bare. Modern class syntax doesn't
explicitly call `bless` from user code.

**Suggested fix:** None.

---

### `print`

**Current TypeLibrary signature:** `arg_types => ['Any'], min_arity => 0, return_type => 'Bool'`

**perldoc -f print:**
> print FILEHANDLE LIST
> print FILEHANDLE
> print LIST
> print
> Prints a string or a list of strings. Returns true if successful.

**Verdict:** **Missing variant — FILEHANDLE form is fully unhandled.**

**Specific issues:**
- The `print FH LIST` form is grammatically distinct: there's no comma
  between FILEHANDLE and LIST. The grammar handles this via
  `IndirectObject`/special parse paths (audit out of scope). At the
  TypeLibrary signature level, both forms collapse to `Any` — which is
  actually fine because `Any` accepts anything, including the FH.
- min_arity 0: correct.
- Return: `Bool` correct.

**Site count in lib/:** 0 parens, 1 bare. Chalk doesn't call `print`.

**Suggested fix:** None at signature level. The variant is grammar-level
not signature-level.

---

### `say`

**Current TypeLibrary signature:** `arg_types => ['Any'], min_arity => 0, return_type => 'Bool'`

**perldoc -f say:**
> say FILEHANDLE LIST
> say FILEHANDLE
> say LIST
> say
> Just like "print", but implicitly appends a newline at the end of the LIST.

**Verdict:** **Same as `print` — Missing variant (grammar-level).**

**Site count in lib/:** 0 parens, 1 bare.

**Suggested fix:** None at signature level.

---

### `return`

**Current TypeLibrary signature:** `arg_types => ['Any'], min_arity => 0, return_type => 'Any'`

**perldoc -f return:**
> return EXPR
> return
> Returns from a subroutine, "eval", "do FILE", "sort" block or regex eval block (but not a "grep", "map", or "do BLOCK" block) with the value given in EXPR. […] If no EXPR is given, returns an empty list in list context, the undefined value in scalar context.

**Verdict:** **Correct (special-cased in TI).**

**Specific issues:**
- arg_types `Any`, min_arity 0: both correct.
- Return: `Any` is a placeholder; TypeInference at line 388-393 of
  `_complete_type` special-cases `return` to propagate the *argument*'s
  type to the enclosing method's return-type registry. So the
  `return_type => 'Any'` in TypeLibrary is a stub overridden by the
  consumer. This is the only signature whose `return_type` is interpreted
  specially.

**Site count in lib/:** 43 parens, 1313 bare. (Bare is overwhelmingly
inflated — `return` appears in many syntactic positions ag matches
crudely.)

**Suggested fix:** None. The override is correct semantics; the stub
flag pattern is consistent with that.

---

### `map`

**Current TypeLibrary signature:** `arg_types => ['Code', 'List'], min_arity => 2, return_type => 'List'`

**perldoc -f map:**
> map BLOCK LIST
> map EXPR,LIST
> Evaluates the BLOCK or EXPR for each element of LIST […] In scalar context, returns the total number of elements so generated. In list context, returns the generated list.

**Verdict:** **Correct (with cross-effect to Bug 1).**

**Specific issues:**
- First arg `Code`: correct (BLOCK is code-typed; EXPR with comma is
  also code-shaped per the alt 2/3 grammar handling).
- Second arg `List`: correct in principle.
- min_arity 2: correct.
- Return: `List` for list context, `Int` (count) for scalar context.
  Context-dependence again. Same issue as `keys`/`splice`.

**Bug 1 cross-reference:** Bug 1 from the RCA shows that
`type_satisfies('Int', 'List')` rejects literal lists. The signature here
is correct; the bug is in `type_satisfies`. Not a TypeLibrary signature
defect.

**Site count in lib/:** 1 parens, 16 bare.

**Suggested fix:** None at signature level. The Bug 1 fix lives in
`type_satisfies`.

---

### `grep`

**Current TypeLibrary signature:** `arg_types => ['Code', 'List'], min_arity => 2, return_type => 'List'`

**perldoc -f grep:** Same shape as `map`. Returns list (or count in scalar).

**Verdict:** **Correct.**

**Site count in lib/:** 1 parens, 2 bare.

---

### `sort`

**Current TypeLibrary signature:** `arg_types => ['List'], min_arity => 1, return_type => 'List'`

**perldoc -f sort:**
> sort SUBNAME LIST
> sort BLOCK LIST
> sort LIST
> In list context, this sorts the LIST and returns the sorted list value. In scalar context, the behaviour of "sort" is undefined.

**Verdict:** **Missing variant + Mostly correct.**

**Specific issues:**
- The 1-entry `arg_types => ['List']` covers `sort LIST`. The block-first
  forms (`sort BLOCK LIST` and `sort SUBNAME LIST`) are handled at the
  grammar layer via alt 2/3 dispatch (audit out of scope). With
  `sig_offset = 1` for alt 2/3, the BLOCK position is at index 0 of
  arg_types — but arg_types[0] is `List`, not `Code`. Confirmed by
  reading `TypeInference.pm:369`:
  ```perl
  my $sig_offset = ($alt_idx == 2 || $alt_idx == 3) ? 1 : 0;
  ```
  For `sort`, alt 2/3 sig_offset=1 means item_types[0] is checked against
  `arg_types[0+1]` = (undefined, falls through to `arg_types[-1]` =
  `List`). So all positions get checked against `List`. That's actually
  what we want — once the BLOCK is consumed, the rest is the LIST.
- min_arity 1: covers `sort @x` (1 arg). For `sort BLOCK LIST` the
  arity-with-offset becomes 2. The signature itself is correct; the
  alt-dispatch handles the rest.
- Return: `List` — context dependence again (scalar context is undefined
  per perldoc; list context returns the list).

**Site count in lib/:** 3 parens, 50 bare.

**Suggested fix:** None.

---

## Type vocabulary gaps

### Gap 1: Union types

**Signatures requiring unions:**
- `split`'s first arg should be `Regex|Str`. **High priority** — Bug 6 anchor.
- `keys`/`values`/`each`'s first arg could be expressed as `Hash|Array`,
  though the existing `List` supertype is a usable interim because both
  Hash and Array are subtypes of List in TypeLibrary.

**Current workaround:** None for `split` (yields Bug 6 rejection); `List` for
the hash-or-array trio.

**Suggested resolution:** Two options:
1. Add `Regex|Str` as a parsed union in `arg_types`. Implementation: split
   on `|` in `type_satisfies`, accept if any branch satisfies. ~5 lines.
2. Add a synthetic `Pattern` type (parent: `Scalar`, children: `Regex`,
   `Str`) used only by `split`. Less general but fits the existing
   bitfield model. Would need a hierarchy entry and bitfield assignment.

Option 1 is more honest about Perl semantics (the `Regex|Str` distinction
arises naturally from coercion). Option 2 is a one-off and doesn't
generalize. **Recommendation: Option 1, gated by a design pass.**

### Gap 2: Refinement types — `Int` vs `Num`

**Signatures incorrectly using `Num` where `Int` is the documented type:**
- `splice` OFFSET, LENGTH (positions 1, 2)
- `substr` OFFSET, LENGTH (positions 1, 2)
- `split` LIMIT (position 2)

**Current workaround:** All three use `Num`, which accepts fractional values
that Perl truncates. The acceptance is wider than documented Perl semantics
but does not block valid code (Perl truncates; `Num` accepts the input);
the case where this matters is **error reporting**: `substr($s, 1.5)` is
silently accepted. Low-priority defect — rejecting it would be helpful but
isn't blocking.

**Suggested resolution:** One-line type swap per signature: `Num` → `Int`.

`PositiveInt` would be a further refinement — `chr(NUMBER)` accepts
negatives (per perldoc, "Negative values give the Unicode replacement
character"); array indices accept negatives (Perl's
"negative-index-from-end" semantics). Most builtins documented as accepting
"NUMBER" or "OFFSET" actually do accept negative values, so `Int` (signed)
is correct, not `PositiveInt`.

**Sites where `length`'s return should be `Nat` rather than `Int`** are
present (length is non-negative), but the receivers (`length($s) - 1` etc.)
use `Int` arithmetic, so the refinement adds no consumer value. Skip.

### Gap 3: Context-dependent return types

**Signatures with documented context-dependent returns:**
- `splice` → list of removed elements (list context) / last removed (scalar)
- `keys` → list of keys (list) / count (scalar)
- `values` → list of values (list) / count (scalar)
- `each` → 2-element list (list) / key only (scalar)
- `delete` → list of values (list) / last value (scalar)
- `map` → list (list) / count (scalar)
- `grep` → list (list) / count (scalar)
- `sort` → list (list) / undefined (scalar)
- `split` → list of fields (list) / count (scalar; legacy void-context @_
  overwrite was removed)

**Current workaround:** TypeLibrary picks `List` (or `Bool` for `exists`).
The result is *correct* for the most common (list) context. Scalar context
is silently unhandled.

**Suggested resolution:** Add an optional `return_type_scalar` field to each
signature, or expose a context-typed return:
```perl
return_type => { list => 'List', scalar => 'Int' }
```
The `narrow_type` helper at TypeLibrary:221-236 already supports `Scalar`
context narrowing; what's missing is using the scalar-context entry rather
than always the unitary `return_type`. This is a Decision 5 (flow-typing)
question — the consumer needs to know the *evaluation context* of each
expression, which flow-typing provides naturally.

**Recommendation: defer to Decision 5 / flow-typing.** The architectural
groundwork exists in `narrow_type` but the consumer logic isn't there yet.

### Gap 4: `Any` catch-all — strict-positional vs Any-catchall styles

**Strict-positional signatures** (every position is named):
- `splice`, `substr`, `bless`, `chr`, `ord`, `length`, `chomp`, `chop`,
  `defined`, `ref`, `scalar`

**Variadic-tail-Any signatures** (first N typed, rest collapse):
- `push`, `unshift`, `splice`, `join`, `sprintf`, `print`, `say`, `die`,
  `warn`, `return`

**Other**:
- `split` (3 strict positions, no variadic — rejects 4-arg implicit forms
  via the `arg_types[-1]` fallback in `_complete_type`)
- `keys`/`values`/`each`/`delete`/`exists` (single-position)

**Inconsistency:** `split`'s third position is `Num` (LIMIT), not `Any`.
This means a 4th argument falls through to `Num`. perldoc only documents
3 args. The behavior is fine. But contrast with `substr`'s missing 4th
arg (REPLACEMENT) which under the same fall-through is rejected — see
substr's verdict.

**Principle the file lacks:** "Variadic-tail-Any" is principled when the
language genuinely accepts any flat scalar as a list element (`push`,
`join`, `sprintf`). "Strict-positional" is principled when the
positions have semantic meaning (substr's offset/length). The
inconsistency is *not* random — it tracks Perl's actual semantics fairly
well — but the file doesn't articulate this principle. Documenting it
in a header comment would help future maintainers.

### Gap 5: Lvalue / mutability typing

`chomp`, `chop` mutate their arguments. `delete`, `exists` operate on
specific lvalue forms (hash element, array element, slice). `substr`
can be lvalue (replacement form). The type system has no concept of
`Lvalue` as a constraint; the grammar layer enforces lvalue context for
some operators but not via the type signature.

**Recommendation: do not add an Lvalue type.** The grammar layer is the
right place. Document the implicit reliance on grammar enforcement.

## Cross-references with Audit 5

Audit 5 documented:
- TypeInference's position-dependence (`_sa()` vs `_annotation_semirings()`)
- Side effects (`%_method_returns` registry, FilterComposite compensation)
- The walker contract that Bug 4 and Bug 5 fixes both touched

**No signature in TypeLibrary has correctness that depends on Audit 5's
side-effect inventory.** Signatures are pure data; the consumer
(`_complete_type`) is where the side-effects manifest. The audit confirms
the dataset itself is independent of the runtime mutations.

**`return`'s `return_type => 'Any'` is the one signature whose
*interpretation* is influenced by side-effects.** Specifically, the
`%_method_returns` mutation at TypeInference:388-393 reads `return`'s
argument type and registers it. This is intentional — `Any` here is a
sentinel meaning "the consumer overrides," not "any type accepted."
Worth documenting in TypeLibrary as a comment so future readers don't
"normalize" it to a more specific type and break the override.

## Prioritized fix punch list

Ordered by **severity × site count × fix complexity**.

### Tier 1 — Bug 6 class, blocks legitimate code

1. **`split` first arg `Regex` → `Regex|Str` (or interim `Any`)** — 23
   sites total, blocks string-form `split` (the most common form).
   Requires Vocabulary Gap 1 (union types) or interim `Any`.

2. **`keys`/`values`/`each` first arg `Hash` → `List`** — 145 total sites.
   Single-word change per signature, retires "Too strict" defect across
   three builtins. Drop-in fix; List is supertype of both Hash and Array.

3. **`delete` first arg `Scalar` → `Any` (or `List`)** — 21 sites. Admits
   slice forms. Lower priority because `delete @hash{@keys}` is uncommon
   in lib/, but signature is principle-broken.

### Tier 2 — Wrong arity defects, low-risk fixes

4. **`pop` `min_arity` 1 → 0** — admits `pop;` for `@_`/`@ARGV`. Trivial.

5. **`shift` `min_arity` 1 → 0** — same. 7 total sites, low risk.

6. **`chr` `min_arity` 1 → 0** — admits `chr;`. 2 total sites.

7. **`defined` `min_arity` 1 → 0** — 840 total sites, high site count.
   Bare `defined;` defaults to `$_`. Many `defined` calls in lib/ are
   parens-form so this isn't blocking, but principle is broken.

8. **`ref` `min_arity` 1 → 0** — 221 total sites. Same story.

### Tier 3 — Wrong type (Num → Int), correctness improvements

9. **`splice` OFFSET, LENGTH `Num` → `Int`** — 1 site.
10. **`substr` OFFSET, LENGTH `Num` → `Int`** — 24 sites. Also missing
    REPLACEMENT (4th) variant.
11. **`split` LIMIT `Num` → `Int`** — 23 sites.

### Tier 4 — Architectural / design-pass scope

12. **Context-dependent return types** — Decision 5 / flow-typing
    territory. 9 builtins affected. Not a one-line fix.

13. **Union types as first-class** — needed for split's `Regex|Str` and
    potentially for `Hash|Array` if `List` proves insufficient.
    Design-pass scope.

14. **`pop`/`shift` REPLACEMENT/missing-variant tracking** — current
    `arg_types[-1]` fall-through is clever but masks the absence of
    documented variants. Not blocking.

## Top 5 priority fixes (severity × site count summary)

| Rank | Builtin | Defect | Sites | Fix complexity |
|---|---|---|---|---|
| 1 | `split` | First-arg `Regex` → `Regex\|Str` | 23 | Medium (union types) or low (interim `Any`) |
| 2 | `keys` | `Hash` → `List` | 51 | Trivial (one word) |
| 3 | `values` | `Hash` → `List` | 39 | Trivial |
| 4 | `each` | `Hash` → `List` | 60 | Trivial |
| 5 | `defined` | `min_arity` 0 | 840 | Trivial |

(Sites = parens + bare from `ag` counts, with the caveat that the bare
counts are pattern-imprecise.)

## Vocabulary gaps that warrant a design pass

1. **Union types** (`A|B` syntax in `arg_types`) — needed for `split`,
   useful for several others.
2. **Context-dependent returns** (`return_type` keyed by list/scalar/void
   context) — needed for 9 builtins. Couples to Decision 5.
3. **Refinement types** (`Int` distinguishing from `Num`, `Nat` for
   non-negative) — needed for several positions. Low risk because
   widening `Int` ⊆ `Num` makes the change backward-compatible.

## Cross-references

- RCA: `docs/plans/2026-04-26-bug-1-and-5-rca-and-remediation.md`
- Audit 5: `docs/plans/2026-04-25-audit-5-semiring-contract-reality-findings.md`
- Synthesis: `docs/plans/2026-04-25-phase-a2-synthesis.md` (Decisions 4, 5, 6)
- pvm reference: `~/.claude/projects/-home-perigrin-dev-chalk/memory/pvm_typeinference_reference.md`
- File under audit: `lib/Chalk/Grammar/Perl/TypeLibrary.pm`
- Consumer: `lib/Chalk/Bootstrap/Semiring/TypeInference.pm` `_complete_type`
  (lines 349-419)

End of findings.
