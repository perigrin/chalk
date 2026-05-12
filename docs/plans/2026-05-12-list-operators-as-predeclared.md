# List operators are predeclared functions, not a grammar category

**Status:** Design note, 2026-05-12. No code changes attached.

This note records the architectural framing reached after the failed
Class I attempt at "list-op rightward slurping" (commit `9966de8c`,
reverted as `61ecb184`). It scopes what's actually in/out for Chalk
and what NOT to attempt next.

## The mental model

Built-in list operators (`print`, `sort`, `chmod`, `map`, `grep`,
`unlink`, etc.) are not a grammatically distinct construct in Perl.
They are **pre-declared functions** — perl knows their names and
their argument-shape signatures by virtue of being a built-in. User
functions become similarly known via `sub foo { ... }` declarations
and (optionally) prototypes.

After predeclaration, the parser treats both classes identically:

- Bare-call form (no parens): `f 1, 2, 3` — greedy rightward
- Paren form: `f(1, 2, 3)` — bounded by the closing paren

The difference between built-in and user-defined is at the
**callee-dispatch** level, not at the **argument-shape** level. Per
B::Concise:

```
f 1, 2, 3   →  pushmark, const(1), const(2), const(3), entersub(f)
sort 1,2,3  →  pushmark, const(1), const(2), const(3), sort
```

Same shape; only the final op differs.

## Two distinct bugs in current Chalk

### Bug 1: universal comma-slurping ambiguity

Affects ALL parens-free calls (built-ins AND user functions equally).

```perl
my $x = sort 3, 1, 2;       # parses as sort(3) , 1, 2 — WRONG
my $x = my_func 3, 1, 2;    # parses as my_func(3) , 1, 2 — WRONG (same bug)
```

The grammar's `CallExpression ::= QualifiedIdentifier WS ExpressionList`
is greedy in isolation, but the outer enclosing `ExpressionList`
(`my $x = $RHS_LIST`) is also greedy and can claim the trailing
`, 1, 2` as sibling list items. Both partitions are admitted. The
filter stack picks the wrong one.

**This is NOT a precedence question.** The disambiguation rule is
"the inner parens-free call's ExpressionList wins the trailing
comma items." That's parser greediness, not operator binding.

**Class I attempted to fix this** by encoding "list-operator context"
as a precedence-level marker (level 4.4) and propagating it through
8 sites in the Precedence semiring. The implementation passed the
named-unary-style spec tests (single-list-op cases) but broke
chained patterns:

```perl
my %h; map { $_ } sort keys %h;   # PARSE_FAIL after Class I
```

The chained list-op-after-list-op case was outside the bilateral
spec coverage Class I added. The audit (commit `61ecb184` was the
revert) caught the regression on three real Chalk source files.

**Right home for this fix (deferred):**
- Either a chart-merge preference rule ("prefer the longer
  ExpressionList for parens-free calls") in FilterComposite or
  Precedence's `add()` logic
- Or a `_fixup_stmts.bare_call_slurp` walker branch that
  reassembles `Call(f, [arg1]) , arg2, arg3` post-parse into
  `Call(f, [arg1, arg2, arg3])`

The walker pattern (which we've been *retiring* with the precedence
work) may genuinely be the right layer for parser-greediness
problems — these are not precedence relationships, they're
ambiguity-resolution preferences that don't fit the level-comparison
model.

**Status:** documented gap. Bypass: write parens (`sort(3, 1, 2)`).
The Chalk source corpus uses parens for these calls; no current
self-hosting blocker. The TODOs in
`t/bootstrap/precedence-spec-low-words.t` for chmod/sort/reverse
remain TODO with refined messages pointing here.

### Bug 2: VSO forms (V-Subject-Object)

Some built-ins accept a "subject" argument before the comma list,
distinguishable by the absence of a comma between the subject and
the rest:

```perl
print $FH "hello\n";       # filehandle subject + list
print STDERR "warn\n";     # bareword filehandle subject + list
sort SUBNAME @arr;         # comparator-sub subject + list
```

vs

```perl
print $x, "hello";         # comma after $x — $x is just a list arg, no subject
print "hello";             # no subject — defaults to STDOUT
sort @arr;                 # no subject — default string compare
```

The "no comma" syntactic marker is what disambiguates VSO from VO.
Chalk's grammar today has NO VSO production — `print $FH "x"`
fails to parse entirely.

**Out of scope for Chalk.** Verified: zero VSO call sites exist in
`lib/Chalk/` source (greps for `print STDERR`, `print $FH`,
`sort SUBNAME @arr`, etc. all return zero hits). Chalk consistently
uses the paren form (`print($FH, "x\n")`) where filehandle access
is needed, or avoids VSO entirely.

**Decision:** explicitly do NOT support VSO forms in Chalk-parseable
Perl. If self-hosting later requires reading code that uses VSO
syntax (e.g., upstream CPAN modules), revisit then. The decision
is reversible at any time by adding the appropriate grammar
alternative.

### Block-VSO (out of scope of "out of scope")

The `map BLOCK LIST` / `grep BLOCK LIST` / `sort BLOCK LIST`
forms ARE supported and work today via existing CallExpression
alternatives 2 and 3. These are syntactically distinct from the
filehandle/subname VSO forms because the subject is a `{...}`
block, which the parser disambiguates lexically.

```
CallExpression ::= ...
    | QualifiedIdentifier WS Block WS ExpressionList   # alt 2: V Block LIST
    | QualifiedIdentifier WS Block                      # alt 3: V Block
    ;
```

These alternatives admit `map { $_ * 2 } @arr` directly.

## Lessons learned

### Lesson 1: precedence levels are for operator binding, not for parser state

The named-unary precedence work (commits `2e9e5739`, `4bbe6308`,
`dd2df9cf`) succeeded because L10 IS a precedence level — it
describes how named-unary operators bind relative to neighboring
operators. The fix involved 4-5 sites in the semiring (scan
detection, Atom pass-through, Subscript reject, PostfixExpression
exempt), each implementing a clear binding-priority comparison.

The list-op work (Class I, reverted) failed because L22 "list
operator rightward" is not really a precedence level — it's a
parser-greediness rule that says "slurp everything to the right."
Encoding that as a precedence marker required 8 sites of
special-case propagation, each bypassing standard semiring
semantics. The accumulated state interactions broke chained
contexts.

**Heuristic:** if implementing a "precedence rule" needs more than
~5 special-case sites in the semiring, OR requires the marker to
"survive" multiple unrelated rule completions, the rule is probably
not precedence. It's likely either grammar (add a rule) or a
parser-state concern (use a different layer).

### Lesson 2: grammatical structure follows lexical syntax, not semantic role

Built-in vs user-defined function is a *symbol table* distinction,
not a *grammar* distinction. The grammar can't know which names are
built-in — the symbol table can. Trying to encode built-in-ness in
the grammar produces special-case alternatives that other code paths
have to reason about.

Conversely, when the grammar DOES need to distinguish forms, the
distinction is lexical (e.g., `Block` vs not-Block, presence/absence
of comma). Those are visible to the grammar and can be encoded as
alternatives without needing semantic knowledge.

### Lesson 3: bilateral coverage extends to nesting

The bilateral coverage rule from the named-unary work
(`docs/plans/2026-05-11-step2-second-blocker.md`) requires testing
operators on each side of a new precedence level. Class I added
bilateral tests for individual list operators (chmod, sort, reverse
in isolation) but NOT for chained list-op-after-list-op patterns.
The chained pattern is the one that broke.

**Stronger rule:** when adding a feature that affects how rules
combine in chains, the bilateral coverage must include
multi-level/nested invocations of the feature. For list operators,
that means: test `f LIST`, test `f g LIST`, test `f { ... } g LIST`
— and verify each shape directly, not just that the inner parses
match expectations.

(This rule should be added to CLAUDE.md alongside the existing
bilateral-coverage rule.)

## Implications for the named-unary work

The named-unary fix is unaffected by this analysis. Named unary IS
a precedence relationship — `defined $h{key}` requires choosing
between `Defined(Subscript)` and `Subscript(Defined)` based on which
operator binds tighter. That's exactly the semiring's job.

The list-op work is not a precedence relationship. `sort 1, 2`
choosing between `sort(1, 2)` and `sort(1), 2` isn't about which
operator binds tighter — both readings have the same operators
present, just with different argument-list partitions. The Precedence
semiring isn't the right layer.

## Cross-references

- The reverted Class I implementation: commit `9966de8c`
- The revert: commit `61ecb184`
- The audit that caught the regression: this session's Round 1+2+3
  end-of-session audit, run on 2026-05-12
- The named-unary lesson: `docs/plans/2026-05-11-step2-second-blocker.md`
- The architectural-framing precedent ("precedence levels for
  binding, not state"): this note
- The TODO refinements: `t/bootstrap/precedence-spec-low-words.t`
  L22 subtests (chmod, sort, reverse, print/or)
