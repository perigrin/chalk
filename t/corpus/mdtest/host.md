# Host interface and magic-var graph edges

`$1`..`$9` and `%ENV` per the runtime-free boundary
(`docs/architecture/runtime-free-boundary.md`): a capture var is an OUTPUT of a
regex-match operation — reading `$1` is reading a slot of the match node's
result, a value on a graph edge, not ambient interpreter state. `%ENV` is host
process state read via the plain C `getenv` — the host-interface layer, not
libperl. Both are RF (campaign group G7).

Deferred (zero uses in lib/, tracked follow-up): `@ARGV`/`$0` (argv plumbing),
`$!` (needs failing-syscall ops the slice does not have), I/O config vars, env
WRITES, `$&`/group-0 exposure, and the undef face of a missing `%ENV` key /
failed-match `$N` (composes with the L3 Undef representation later; today a
missing env key reads as the empty string and the corpus only exercises the
set-key path).

## H1 capture read ($1)

Reading `$1` after a match is a `RegexCapture` node taking the match node as
input — the captured bytes are copied into a fresh NUL-terminated buffer at
the offsets the G6 matcher records (every Str value in the backend is
NUL-terminated; no `%MatchResult` struct is materialized).

```perl
# source
use 5.42.0;
my $s = "ab-cd";
$s =~ /(\w+)-(\w+)/;
say($1);
```

```behavior
stdout: ab\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s      = Constant("ab-cd") :Str
%m      = RegexMatch(%s, pattern: "(\w+)-(\w+)") :Bool
%result = RegexCapture(%m, n: 1) :Str
%nl = Constant("\n") :Str
%p  = Print(%result, %nl)
return %p
control: %start -> %p
L: GREEN
```

## H2 guarded capture (the dominant lib/ idiom)

lib/'s 96 `$N` reads overwhelmingly sit behind a match guard:
`if ($x =~ /.../) { ... $1 ... }`. The guarded form reads the capture only on
the matched path; the ternary face here is Int (`length($1)`).

```perl
# source
use 5.42.0;
my $s = "foo";
say($s =~ /(o+)/ ? length($1) : 0);
```

```behavior
stdout: 2\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s      = Constant("foo") :Str
%m      = RegexMatch(%s, pattern: "(o+)") :Bool
%cap    = RegexCapture(%m, n: 1) :Str
%len    = Length(%cap) :Int
%zero   = Constant(0) :Int
%result = TernaryExpr(%m, %len, %zero) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%result : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## H3 environment read (%ENV)

`$ENV{KEY}` is an `EnvRead` node lowering to the host C `getenv` (+ a runtime
`strlen` for the value length). The runner sets `CHALK_G7_TEST=hostval` before
running this case; both the perl oracle and lli inherit the environment, so
the declared return is exact under the runner.

```perl
# source
use 5.42.0;
say($ENV{CHALK_G7_TEST});
```

```behavior
stdout: hostval\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%result = EnvRead(key: "CHALK_G7_TEST") :Str
%nl = Constant("\n") :Str
%p  = Print(%result, %nl)
return %p
control: %start -> %p
L: GREEN
```
