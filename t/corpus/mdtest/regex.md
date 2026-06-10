# Regex

Regex match, compiled-regex (qr//), and substitution idioms.

All cases in this topic are L: GAP — but the GAP means "not modelled YET," not
"needs the interpreter." Core regex is runtime-free (RF): a literal pattern is a
compile-time-known mini-language, and the RF answer is a regex sub-compiler
(pattern -> DFA/NFA/bytecode matcher) emitted runtime-free, producing
`(matched?, $1, $2, ...)`. `qr//` compiles a matcher value; `s///` is match + Str
rewrite (the Str part riding on G3's Str representation). These are GAPs only
until the regex sub-compiler (campaign group G6) and Str (G3) are modelled, NOT a
libperl/perl-regex-engine dependency. (The genuinely-OOS regex feature is only
`(?{ perl code })` — embedded runtime code; core patterns are RF.) The behavior
is still specified by the perl oracle; the GAP records the honest reason a
compile-time-only LLVM path cannot yet lower these idioms.

Archive sources: `archive/pu-2026-03-24:t/corpus/ir/regex-match.chalk` (R1
adapted to a runnable form), `archive/pu-2026-03-24:t/corpus/ir/regex-qr.chalk`
(R2 adapted), and a substitution variant (R3).

## R1 regex match (=~)

The `=~` operator applies a literal regex to a string subject. The literal
pattern is a compile-time-known mini-language: a regex sub-compiler lowers it to a
DFA/NFA matcher that produces `(matched?, $1, $2, ...)` runtime-free. The IR is a
GAP only until the regex sub-compiler (G6) is modelled, NOT a libperl/regex-engine
dependency.

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
subsequent `=~` is an indirect application of the same matcher. The IR is a GAP
only until the regex sub-compiler (G6) is modelled, NOT a libperl dependency.

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
L: GAP(qr// is RF: compiles a matcher value via the regex sub-compiler (G6); GAP only until G6 is modelled, NOT a libperl dependency)
```

## R3 regex substitution (s///)

The `s///` operator is a match followed by a Str rewrite. The match rides on the
regex sub-compiler (G6) and the rewrite rides on G3's Str representation — both
runtime-free. The IR is a GAP only until the regex sub-compiler (G6) and Str (G3)
are modelled, NOT a libperl/regex-engine dependency.

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
L: GAP(s/// is RF: match (regex sub-compiler, G6) + Str rewrite (G3); GAP only until G6+G3 are modelled, NOT a libperl dependency)
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
