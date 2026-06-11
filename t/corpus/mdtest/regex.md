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
