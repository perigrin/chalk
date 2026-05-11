# `exists` precedence: forensic investigation

**Status:** Read-only investigation, 2026-05-11. No code changes. Companion to
`docs/plans/2026-05-11-precedence-named-unary-plan.md` Step 2.

## 1. Question

`exists` appears in Chalk's `@NAMED_UNARY` list (`lib/Chalk/Grammar/Perl/PrecedenceTable.pm:57-58`,
introduced in commit `2e9e5739`) and would receive perlop L10 named-unary
precedence (level=50, assoc=nonassoc) under Step 2 of the precedence plan. A
prior subagent flagged that perlop documents `exists` separately from "Named
Unary Operators", and that `exists` has shape restrictions on its argument
(hash/array element or `&sub`) that are not characteristic of the named-unary
class. Is the L10 named-unary treatment correct? We need authoritative
evidence from perlop, perlfunc, and the real perl interpreter's behavior.

## 2. What perlop says

### Precedence table (`perlop.pod:128-153`)

The full precedence table, highest to lowest:

```
left        terms and list operators (leftward)
left        ->
nonassoc    ++ --
right       **
right       ! ~ ~. \ and unary + and -
left        =~ !~
left        * / % x
left        + - .
left        << >>
nonassoc    named unary operators
nonassoc    isa
chained     < > <= >= lt gt le ge
chain/na    == != eq ne <=> cmp ~~
...
```

`exists` is **not enumerated by name** in this table; it falls (or would fall)
in the unnamed "named unary operators" slot.

### "Named Unary Operators" section (`perlop.pod:504-539`)

```
=head2 Named Unary Operators
X<operator, named unary>

The various named unary operators are treated as functions with one
argument, with optional parentheses.

If any list operator (C<print()>, etc.) or any unary operator (C<chdir()>, etc.)
is followed by a left parenthesis as the next token, the operator and
arguments within parentheses are taken to be of highest precedence,
just like a normal function call.  For example,
because named unary operators are higher precedence than C<||>:

    chdir $foo    || die;       # (chdir $foo) || die
    ...

but, because C<"*"> is higher precedence than named operators:

    chdir $foo * 20;    # chdir ($foo * 20)
    ...
```

Critically: the section **does not list which functions are named-unary**.
perlop relies on perlfunc's per-function entries to indicate this implicitly.
The section title at line 504 is the only explicit cross-reference for the
precedence row at line 138.

### Worth noting

The only other mention of `exists` in `perlop.pod` is in code examples for
the smartmatch/~~ documentation (lines 742, 756, 758, 764) — used as a
function call inside `grep { ... }` blocks, not as a precedence example.
There is **no perlop section that singles out `exists` as anything other than
a named-unary operator**.

## 3. What perlfunc says

### `exists EXPR` (`perlfunc.pod:2698-2763`)

```
=item exists EXPR

Given an expression that specifies an element of a hash, returns true if the
specified element in the hash has ever been initialized, even if the
corresponding value is undefined.

    print "Exists\n"    if exists $hash{$key};
    print "Defined\n"   if defined $hash{$key};
    print "True\n"      if $hash{$key};
```

Restriction (line 2738-2746):

```
Note that the EXPR can be arbitrarily complicated as long as the final
operation is a hash or array key lookup or subroutine name:

    if (exists $ref->{A}->{B}->{$key})  { }
    if (exists $hash{A}{B}{$key})       { }
    ...
```

Error case (line 2759-2763):

```
Use of a subroutine call, rather than a subroutine name, as an argument
to C<exists> is an error.

    exists &sub;    # OK
    exists &sub();  # Error
```

The form `EXPR` (with one capital-letter argument) is the same form used for
`defined EXPR` and is the standard signature for named-unary functions in
perlfunc.

### `defined EXPR` (`perlfunc.pod:1711-1779`)

```
=item defined EXPR

=item defined

Returns a Boolean value telling whether EXPR has a value other than the
undefined value...  If EXPR is not present, $_ is checked.
```

`defined` has two signatures (with and without EXPR). `exists` has only one.
Otherwise their entries are structurally parallel. **perlfunc does not
categorize either as named-unary explicitly** — that classification is
implicit in the precedence table at `perlop.pod:138`.

### `delete EXPR` (`perlfunc.pod:1780+`)

```
=item delete EXPR

Given an expression that specifies an element or slice of a hash,
C<delete> deletes the specified elements from that hash...
```

`delete` has the same argument-shape restriction as `exists` (must be a hash
element/slice, array element/slice, or subroutine name).

### Categorization (`perlfunc.pod:182-189`)

```
=item Functions for real %HASHes

L<C<delete>>, L<C<each>>, L<C<exists>>, L<C<keys>>, L<C<values>>
```

The "Functions by Category" index groups `exists` with hash functions, NOT in
any "named-unary" category. (perlfunc does not have a "named-unary" category;
that classification only lives in perlop's precedence table.)

## 4. What perl does (empirical: B::Deparse + B::Concise)

All commands run with `$HOME/.local/share/pvm/versions/5.42.0/bin/perl`.

### Deparse table

| Expression | Deparse output | Parsed as |
|---|---|---|
| `exists $h{k}` | `exists $h{'k'};` | `exists($h{k})` |
| `!exists $h{k}` | `not exists $h{'k'};` | `!exists($h{k})` |
| `exists $a[0]` | `exists $a[0];` | `exists($a[0])` |
| `exists &subname` | `exists &subname;` | `exists(&subname)` |
| `exists $h{k} + 1` | **compile error**: "exists argument is not a HASH or ARRAY element or a subroutine" | `exists($h{k} + 1)` — error from arg-shape check |
| `1 + exists $h{k}` | `1 + exists $h{'k'};` | `1 + exists($h{k})` |
| `defined exists $h{k}` | `defined exists $h{'k'};` | `defined(exists($h{k}))` |
| `exists defined $h{k}` | **compile error**: "exists argument is not a HASH or ARRAY element or a subroutine" | `exists(defined($h{k}))` — error from arg-shape check |
| `(exists $h{k}) + 1` | `exists $h{'k'} + 1;` | Same surface form as the failing case |
| `defined $h{k} + 1` | `defined $h{'k'} + 1;` | `defined($h{k} + 1)` |

Key observations from the table:

- `exists $h{k} + 1` is a **compile-time error**, not a parse error. The
  parser successfully forms `exists($h{k} + 1)`; the failure comes from
  perl's argument-shape validation pass on the EXISTS op. This is exactly
  what would happen if `exists` is a named-unary at L10 (binding looser than
  `+`).
- `defined $h{k} + 1` deparses identically and is the same parse:
  `defined($h{k} + 1)`. The two functions bind their arguments identically.
- `(exists $h{k}) + 1` deparses to `exists $h{'k'} + 1` — Deparse drops the
  parens because the named-unary's default low-precedence binding is what
  would otherwise be ambiguous. (Round-tripping `exists $h{'k'} + 1` back
  through Perl would now error, showing the ambiguity is real.)

### B::Concise -exec confirmation for `defined`

```
$ perl -MO=Concise,-exec -e 'defined $h{k} + 1'
1  <0> enter v
2  <;> nextstate(main 1 -e:1) v:{
3  <+> multideref($h{"k"}) sK
4  <$> const[IV 1] s
5  <2> add[t2] sK/2
6  <1> defined vK/1     <-- defined is OUTER; add is its child
7  <@> leave[1 ref] vKP/REFC

$ perl -MO=Concise,-exec -e '1 + defined $h{k}'
1  <0> enter v
2  <;> nextstate(main 1 -e:1) v:{
3  <$> const[IV 1] s
4  <+> multideref($h{"k"}) sK
5  <1> defined sK/1     <-- defined wraps $h{k}; add wraps both
6  <2> add[t2] vK/2
7  <@> leave[1 ref] vKP/REFC
```

This is the canonical named-unary binding: when followed by `+`, it eats the
right-hand side; when preceded by `+`, it stops at the variable.

### Tokenizer-level evidence (perl source)

From `/home/perigrin/dev/perl5/toke.c`:

```c
case KEY_defined:
    UNI(OP_DEFINED);

case KEY_delete:
    UNI(OP_DELETE);

case KEY_exists:
    UNI(OP_EXISTS);

case KEY_exit:
    UNI(OP_EXIT);
```

(toke.c:8124-8163.) The `UNI(f)` macro at `toke.c:280` is defined as
`UNI3(f,XTERM,1)` — the **named-unary** classifier in the lexer. perl's own
tokenizer puts `exists` in the same class as `defined`, `delete`, `ref`,
`scalar`, `chr`, `ord`, etc. There is **no separate classification** for
`exists` at the parser level. The hash/array/sub argument-shape restriction
is enforced **post-parse** by op-walking in `op.c`, not by the grammar.

## 5. What Chalk does today (probe output)

Probe: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib -It/bootstrap/lib /tmp/probe-precedence.pl`.

| Source | Chalk IR shape (paraphrased) |
|---|---|
| `my $x = exists $h{k};` | `VarDecl($x, Subscript(Call(exists, [$h]), k, hash))` |
| `my $y = !exists $h{k};` | `VarDecl($y, Subscript(Not(Call(exists, [$h])), k, hash))` |
| `my $z = exists $a[0];` | `VarDecl($z, Subscript(Call(exists, [$a]), 0, array))` |
| `my $w = exists $h{k} + 1;` | `VarDecl($w, Add(+, Subscript(Call(exists, [$h]), k, hash), 1))` |

Every one of these is **wrong** in the same way: the subscript is OUTSIDE
the `Call(exists, ...)` wrapper, when perl puts it INSIDE. The probe
confirms that current Chalk has exactly the bug Step 2 of the precedence
plan is designed to fix — for `exists`, not just for `defined`.

Note: this is the **same** wrong-shape pattern that
`_fix_postfix_chain.subscript_over_builtin` (Actions.pm) rewrites
post-parse for the other named-unaries. The fixup almost certainly
papers over the issue for `exists` in real source today; the probe is
showing the raw pre-fixup parse to expose what the precedence semiring
is actually producing.

## 6. Verdict

**(a) Keep `exists` in `@NAMED_UNARY` at L10.**

Evidence:

- **perl's own tokenizer classifies `exists` as named-unary** (`toke.c:8158-8159`,
  `UNI(OP_EXISTS)`), identical to `defined`, `delete`, `ref`, `scalar`, etc.
  The argument-shape restriction (hash/array element / `&sub`) is enforced
  *post-parse*, not at parse time, and does not affect precedence binding.
- **perl's parser binds `exists` and `defined` identically.** B::Concise
  shows `exists $h{k} + 1` parses as `exists($h{k} + 1)` (then errors at
  shape-check), and `defined $h{k} + 1` parses as `defined($h{k} + 1)`. The
  precedence is the same; only the post-parse validation differs.
- **perlop's separate documentation of `exists` is a perlfunc-categorization
  artifact, not a precedence statement.** perlop lists `exists` only in
  code examples and never assigns it to any non-named-unary precedence row.
  perlfunc groups it with hash functions by domain, not by parser class.
- **Chalk's current shape for all four test cases is wrong in the same way
  as `defined`** — confirming that `exists` belongs in the same Step 2 fix.

## 7. Implications for Step 2

Step 2 should proceed unchanged for `exists`. The plan's current
`@NAMED_UNARY` list (`PrecedenceTable.pm:57-58`) is correct: `defined exists
ref scalar length chr ord` is precisely the cluster of perl's `UNI(...)`-classified
functions that take exactly one argument and have no list-operator behavior.
The probe in §5 demonstrates that the bug Step 2 fixes exists for `exists`
just as it does for `defined`, so this investigation gives **no reason to
delay or refactor Step 2**. The argument-shape restriction on `exists` (and
`delete`) is a separate concern — it would be enforced in IR validation or
codegen, downstream of the precedence semiring, and is independent of the
L10 binding rule. Worth noting in the Step 2 plan as a follow-on: a TODO
test for `exists $h{k} + 1` should NOT assert successful parse — perl
itself rejects this — so the spec test should either accept the IR for
`exists($h{k} + 1)` and defer the error to a later pass, or mark it as a
TODO for later argument-shape validation.
