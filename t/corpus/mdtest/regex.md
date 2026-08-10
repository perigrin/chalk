# Regex

Regex match, compiled-regex (qr//), and substitution idioms.

Core regex is runtime-free (RF): a literal pattern is a compile-time-known
mini-language, and the regex sub-compiler (campaign group G6) lowers it to an
inlined matcher producing `(matched?, $1, $2, ...)` — no libperl, no
perl-regex-engine. `qr//` compiles a matcher value (a `Constant` of
const_type "regex" applied via `Match`); `s///` is match + Str rewrite riding
on G3's Str representation. All cases in this topic are L: GREEN against that
sub-compiler. (The genuinely-out-of-scope regex feature is only
`(?{ perl code })` — embedded runtime code; core patterns are RF. Alternation,
\Q\E, /g and friends are tracked as G6 fast-follows, zhi 019eb073.)

Archive sources: `archive/pu-2026-03-24:t/corpus/ir/regex-match.chalk` (R1
adapted to a runnable form), `archive/pu-2026-03-24:t/corpus/ir/regex-qr.chalk`
(R2 adapted), and a substitution variant (R3).

## R1 regex match (=~)

The `=~` operator applies a literal regex to a string subject. The literal
pattern is a compile-time-known mini-language: the regex sub-compiler lowers it
to an inlined matcher that produces `(matched?, $1, $2, ...)` runtime-free —
no libperl/regex-engine dependency.

Source: `archive/pu-2026-03-24:t/corpus/ir/regex-match.chalk`
(`if ($x =~ m/pattern/) { 1 }` — adapted to a runnable form with concrete values).

```perl
# source
my $s = "foobar";
$s =~ /foo/ ? 1 : 0
```

```behavior
return: 1
context: scalar
```

```ir
%s      = Constant("foobar") :Str
%m      = RegexMatch(%s, pattern: "foo") :Bool
%one    = Constant(1) :Int
%zero   = Constant(0) :Int
%result = TernaryExpr(%m, %one, %zero) :Int
return %result
L: GREEN
```

## R2 qr// compiled regex

The `qr//` operator compiles a regex into a first-class matcher value. The regex
sub-compiler lowers the literal pattern to that matcher value runtime-free, and a
subsequent `=~` is an application of the same matcher (`Match` over a `Constant`
of const_type "regex" — statically resolved, no libperl dependency).

Source: `archive/pu-2026-03-24:t/corpus/ir/regex-qr.chalk`
(`my $re = qr/\d+/;` — adapted to a runnable form that also exercises the match).

```perl
# source
my $re = qr/foo/;
my $s = "foobar";
$s =~ $re ? 1 : 0
```

```behavior
return: 1
context: scalar
```

```ir
%qr     = Constant("foo", const_type: "regex") :Regex
%s      = Constant("foobar") :Str
%m      = Match(%s, %qr) :Bool
%one    = Constant(1) :Int
%zero   = Constant(0) :Int
%result = TernaryExpr(%m, %one, %zero) :Int
return %result
L: GREEN
```

## R3 regex substitution (s///)

The `s///` operator is a match followed by a Str rewrite. The match rides on the
regex sub-compiler and the rewrite rides on G3's Str representation — both
runtime-free, no libperl/regex-engine dependency.

```perl
# source
my $s = "foobar";
$s =~ s/foo/baz/;
$s
```

```behavior
return: bazbar
context: scalar
```

```ir
%s      = Constant("foobar") :Str
%result = RegexSubst(%s, pattern: "foo", replacement: "baz") :Str
return %result
L: GREEN
```

## R4 anchored match (^)

A `^`-anchored pattern matches only at the start of the subject. The regex
sub-compiler (G6 T1) lowers `^` by collapsing the slide loop to offset 0: the
matcher tries the literal once at position 0 and reports no-match if it fails
there, rather than sliding. Runtime-free, libperl-free.

```perl
# source
my $s = "foobar";
$s =~ /^foo/ ? 1 : 0
```

```behavior
return: 1
context: scalar
```

```ir
%s      = Constant("foobar") :Str
%m      = RegexMatch(%s, pattern: "^foo") :Bool
%one    = Constant(1) :Int
%zero   = Constant(0) :Int
%result = TernaryExpr(%m, %one, %zero) :Int
return %result
L: GREEN
```

## R5 character class match

A character class `[...]` matches one subject byte against a set of ranges and
members; `\d`/`\w`/`\s` are shorthand classes and `.` matches any byte except
newline. The regex sub-compiler (G6 T2) lowers each class atom to a range-icmp
predicate over the loaded byte — runtime-free, libperl-free.

```perl
# source
my $s = "a9z";
$s =~ /[0-9]/ ? 1 : 0
```

```behavior
return: 1
context: scalar
```

```ir
%s      = Constant("a9z") :Str
%m      = RegexMatch(%s, pattern: "[0-9]") :Bool
%one    = Constant(1) :Int
%zero   = Constant(0) :Int
%result = TernaryExpr(%m, %one, %zero) :Int
return %result
L: GREEN
```

## R6 quantified identifier match

Greedy quantifiers (`*`, `+`, `?`, `{n,m}`) make an atom consume a variable
number of bytes. The regex sub-compiler (G6 T3) emits a greedy-consume loop
plus a backoff loop per quantified atom, so a failed continuation backs off
one repetition and retries (correct greedy backtracking via runtime loop
structure). This case is the dominant lib/ pattern shape: anchored class +
quantified class (a Perl identifier check).

```perl
# source
my $s = "foo_1";
$s =~ /^[A-Za-z_][A-Za-z0-9_]*$/ ? 1 : 0
```

```behavior
return: 1
context: scalar
```

```ir
%s      = Constant("foo_1") :Str
%m      = RegexMatch(%s, pattern: "^[A-Za-z_][A-Za-z0-9_]*$") :Bool
%one    = Constant(1) :Int
%zero   = Constant(0) :Int
%result = TernaryExpr(%m, %one, %zero) :Int
return %result
L: GREEN
```

## R7 negated match (!~)

The `!~` operator is the negation of `=~`. Perl compiles it to a `match` op
wrapped in a `not` op (there is no distinct notmatch op), so the producer emits
`Not(RegexMatch(...))` — the already-lowered `RegexMatch` matcher feeding the
runtime-free `Not` (an i1 xor). No dedicated NotMatch lowering is needed; the
negation rides on the existing Match + Not arms. This case uses a pattern that
DOES match the subject, so the negation must flip a real match to false (the
ternary takes the else arm) — a bilateral check against R1's matching `=~`.

```perl
# source
my $s = "hello";
$s !~ /ell/ ? 111 : 222
```

```behavior
return: 222
context: scalar
```

```ir
%s      = Constant("hello") :Str
%m      = RegexMatch(%s, pattern: "ell") :Bool
%nm     = Not(%m) :Bool
%t      = Constant(111) :Int
%e      = Constant(222) :Int
%result = TernaryExpr(%nm, %t, %e) :Int
return %result
L: GREEN
```

## R8 unbound match reads $_ (t/base/pat.t blocker)

A match with no `=~` binding takes its subject from `$_`. In the optree that
subject is not an operand at all: the op carries no pad target and pushes
nothing (measured, perl 5.42: `targ=0 flags=0x02`), where a lexical subject is
the pad target (`targ=1 flags=0x02`) and a package subject is pushed with
OPf_STACKED (`targ=0 flags=0x46`).

The producer read `$op->targ` unconditionally, so both targ-less forms got a
fabricated read of pad slot 0 — emitted as `PadAccess(varname: "$?0")`, which
names no variable. That reached the backend unstamped and GAPped there, and the
GAP text blamed TypeInference ("fix TypeInference so this node carries an
explicit repr"). Stamping it would have compiled a match against an
uninitialized slot: a silent wrong answer in place of a loud refusal.

`$_` is the package scalar `main::_`, so an unbound match now builds the SAME
`StashAccess` node an explicit `$_ = ...` store builds. The two hash-cons to one
node, which is what makes the read observe the store (measured: one
`StashAccess` with both the `Assign` and the `RegexMatch` as consumers) and what
gives the read its Str repr, exactly as A19 describes for `our $g`.

```perl
# source
$_ = "test";
/^test/ ? 1 : 0
```

```behavior
return: 1
context: scalar
```

```ir
%c      = Constant("test") :Str
%ul     = StashAccess(stash_name: "main", var_name: "_") :Str
%st     = Assign(%ul, %c) :Str
%ur     = StashAccess(stash_name: "main", var_name: "_") :Str
%m      = RegexMatch(%ur, pattern: "^test") :Bool
%one    = Constant(1) :Int
%zero   = Constant(0) :Int
%result = TernaryExpr(%m, %one, %zero) :Int
return %result
control: %st
L: GREEN
```

## R8b unbound match against a NON-matching $_ (bilateral)

R8's partner: the identical program with only the STORED value changed, so the
same pattern must now fail. This is the case that discriminates a real read of
`$_` from the fabricated slot-0 read — an uninitialized slot does not match
`^test` either, so R8's polarity alone would pass against the bug. Only a pair
that changes the stored value and sees the answer change proves the match is
reading what the store wrote.

```perl
# source
$_ = "nope";
/^test/ ? 1 : 0
```

```behavior
return: 0
context: scalar
```

```ir
%c      = Constant("nope") :Str
%ul     = StashAccess(stash_name: "main", var_name: "_") :Str
%st     = Assign(%ul, %c) :Str
%ur     = StashAccess(stash_name: "main", var_name: "_") :Str
%m      = RegexMatch(%ur, pattern: "^test") :Bool
%one    = Constant(1) :Int
%zero   = Constant(0) :Int
%result = TernaryExpr(%m, %one, %zero) :Int
return %result
control: %st
L: GREEN
```

## R9 match bound to a PACKAGE scalar (OPf_STACKED subject)

The third subject form: `$g =~ /re/` where `$g` is a package scalar. The subject
is pushed onto the stack by a preceding `gvsv` and the match op carries
OPf_STACKED (`0x40`) with no pad target — so it hit the same fabricated slot-0
read as R8 and GAPped identically. The subject is popped from the stack now.

A RUNTIME pattern applied to a pushed subject (`$g =~ $re`) puts TWO values on
the stack and is a declared GAP: the pop order would have to be established
before either could be taken safely, and guessing it is how a subject and a
matcher get swapped silently.

```perl
# source
our $g = "test";
$g =~ /^test/ ? 1 : 0
```

```behavior
return: 1
context: scalar
```

```ir
%c      = Constant("test") :Str
%gl     = StashAccess(stash_name: "main", var_name: "g") :Str
%st     = Assign(%gl, %c) :Str
%gr     = StashAccess(stash_name: "main", var_name: "g") :Str
%m      = RegexMatch(%gr, pattern: "^test") :Bool
%one    = Constant(1) :Int
%zero   = Constant(0) :Int
%result = TernaryExpr(%m, %one, %zero) :Int
return %result
control: %st
L: GREEN
```
