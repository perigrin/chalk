# Regex

Regex match, compiled-regex (qr//), and substitution idioms.

All cases in this topic are L: GAP — regex operations require a Str/Scalar (SV*)
representation for the subject string and the regex engine for matching. Neither
is part of the runtime-free Int/Num lowering slice. The behavior is still
specified by the perl oracle; the GAP records the honest reason a
compile-time-only LLVM path cannot yet lower these idioms.

Archive sources: `archive/pu-2026-03-24:t/corpus/ir/regex-match.chalk` (R1
adapted to a runnable form), `archive/pu-2026-03-24:t/corpus/ir/regex-qr.chalk`
(R2 adapted), and a substitution variant (R3).

## R1 regex match (=~)

The `=~` operator applies a literal regex to a string subject. At the IR level
this requires a Str-typed node for the subject and a RegexMatch node whose
operands carry Scalar/SV* representations. Neither the Str/Scalar allocation
nor the regex engine call is runtime-free lowerable in the current Int/Num
arithmetic slice.

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
L: GAP(regex match needs Str/Scalar + regex engine; not runtime-free lowerable)
```

## R2 qr// compiled regex

The `qr//` operator compiles a regex into a first-class regex object. The IR
would need a Scalar/regex-object representation for the compiled pattern, and
a subsequent `=~` still invokes the regex engine at runtime. Neither the
regex-object allocation nor the match call is in the runtime-free lowering
slice.

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
L: GAP(qr compiles a regex object; needs Scalar/regex representation; not runtime-free lowerable)
```

## R3 regex substitution (s///)

The `s///` operator mutates the subject string in place. This requires both a
Str-typed mutable binding (VarDecl + PadAccess) and a RegexSubst node that
invokes the regex engine and performs string replacement. The mutating Str
binding and the regex engine call are outside the runtime-free lowering slice.

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
L: GAP(s/// needs mutable Str/Scalar binding + regex engine; not runtime-free lowerable)
```
