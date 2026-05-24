# `class` as Load-Time Builtin — Rejected

**Date:** 2026-05-24
**Status:** Architectural question raised and resolved.
**Decision:** Keep the current parse-time MOP::Class construction.
**Context:** Surfaced during Phase 5b snippet-wrapping work.

## The question

During Phase 5b, I was wrapping bare-expression test snippets like
`if (1) { 42 }` in `class TestC { method m { ... } }` so they could
exercise the production MOP+scheduler codegen path. This raised a
larger question: should Chalk treat `class Foo { ... }` as a *load-
time builtin call* — matching Perl 5.42's actual runtime semantics
— rather than as a parse-time declaration?

The load-time-builtin model would mean:

- The parser produces `Call(builtin='class', args=['Foo', BODY])` for
  every `class` declaration. No MOP::Class entry is created at parse
  time.
- The MOP::Class object is allocated at *load time* (when the `class`
  call runs).
- The class body executes in a scope where `field`, `method`, `sub`,
  etc. are themselves builtin calls that register on the current
  class.
- File-scope statements and class declarations become uniform: both
  are just sequences of statements executed in order.

This matches Python (`class Foo: ...` constructs a class object at
import time), Ruby (`class Foo; ...; end` executes the body with the
class as `self`), Smalltalk (class definitions are messages sent to
the system), and CRuby's iseq compiler (`defineclass` instruction
takes a body-iseq executed at runtime).

It also matches Perl 5.42's actual semantics: real Perl runs class
bodies at load time. `field $x = expensive_function();` in real Perl
calls `expensive_function()` when the class is declared, not at
parse time.

## Why I argued for it

In Chalk's current design the parser walks `class Foo { ... }` and
populates a `MOP::Class('Foo')` directly from the parsed body. Method
declarations become `MOP::Method` entries; field declarations become
`MOP::Field` entries. Everything is parse-time metadata.

This means Chalk cannot correctly handle:

```perl
class Foo {
    my $start_time = time();
    field $created :reader = $start_time;
}
```

Real Perl runs `time()` once at class-declaration time, capturing the
result in `$start_time`, which then becomes the default-init for
`$created`. Chalk's parser-driven model has no mechanism for "code
that runs when the class is defined"; the `my $start_time = time()`
line is body content with no execution context.

I framed this as Chalk's MOP being a *divergence* from Perl semantics
that needs eventual repair.

## Why I was wrong

Looked at Matz's Spinel — the AOT Ruby compiler released in 2026.
Spinel is the relevant prior art: it's a self-hosting AOT compiler
for a dynamic OO language whose runtime model is even more permissive
than Perl's (Ruby executes class bodies as fully ordinary code).
Spinel deliberately *rejects* the load-time-execution model and
treats class bodies as parsed declarations.

Specifically, Spinel:

- Performs **whole-program type inference** across the entire program
  at compile time. This requires the class hierarchy to be statically
  determinable.
- Has a `collect_all` analysis pass that "registers every class,
  module, top-level method, instance method, class method, ivar
  declaration" in a single AST walk — parse-time, not runtime.
- Has separate `infer_class_body_call_types` and `infer_main_call_types`
  passes — class body code and top-level code are distinct *static*
  contexts, both analyzed at compile time.
- Explicitly **forbids** `eval`, `send`, `method_missing`,
  `define_method`, and threads — the features whose Ruby semantics
  *require* load-time class construction.

In exchange Spinel gets static method dispatch, whole-program type
inference, and reported 11.6× speedups over CRuby.

This is the classic AOT/dynamic tradeoff. Spinel chose AOT. The
constraint set Spinel imposes is precisely the set of Ruby features
that *require* the load-time execution model. Drop them and the
static parse-time model suffices.

## Why this validates Chalk's design

Chalk is also an AOT compiler. Chalk's restricted Perl subset already
excludes the analogous Perl features:

- No `eval STRING`
- No symbol table mutation
- No dynamic method dispatch via `$obj->$method_name`
- No `*Foo::method = sub { ... }` glob assignment
- No `AUTOLOAD`
- No threads (yet; not on the roadmap as a Chalk feature either)

These are exactly the Perl analogs of the Ruby features Spinel bans.
Chalk has independently arrived at the same constraint set Spinel
chose, because the same AOT-friendly subset emerges from the same
optimization-vs-flexibility tradeoff.

Therefore: Chalk's parser-driven `MOP::Class` construction is **not**
a divergence from Perl semantics that needs fixing. It is the same
deliberate AOT design choice Spinel made, justified by the same
constraints. Bare/unwrapped top-level statements are out of Chalk's
purview by the same logic — they are exactly the kind of load-time
executable content that AOT compilers exclude in exchange for static
analyzability.

For programs that *need* load-time class construction (`field $x =
expensive();`, conditional class declarations, etc.), the right tool
is the Perl interpreter, not Chalk. Chalk is for the AOT-friendly
subset, where parse-time metadata is sufficient.

## What this means concretely

1. **Keep parse-time `MOP::Class` construction.** No change to
   `Actions::ClassDecl`. No `class` builtin/keyword.

2. **Keep the bare-statement exclusion.** Chalk's `Program` action
   collects bare statements into `other_stmts`, but that field has no
   consumers in the MOP-driven codegen path. After Phase 6 deletes
   `Chalk::IR::Program`, bare statements at file scope simply have no
   IR representation — and that is correct, because they cannot be
   compiled without load-time execution semantics.

3. **Snippet-wrapping is the right migration for legacy tests.**
   Bare-expression test snippets like `if (1) { 42 }` get wrapped in
   `class TestC { method m { ... } }`. This adapts the snippet to
   Chalk's actual source contract; it's not a workaround.

4. **No `MOP::Class->body` field needed.** I'd considered adding one
   for file-scope statements adjacent to class declarations. Reject
   for the same reason: file-scope statements are load-time execution
   content, which Chalk's AOT model excludes. The only file-scope
   content Chalk needs to represent is `use` declarations (handled by
   `MOP::Class->imports`), and those are already covered.

5. **Future Chalk source must comply.** Self-hosting Chalk parsing
   itself: every Chalk-target `.pm` file must be expressible as
   imports + a class declaration + (optionally) `1;` for back-compat
   with `use`/`require` callers. Bare top-level expressions, file-
   scope variable declarations, file-scope `BEGIN` blocks are not
   supported and are not planned. Real Chalk-source `.pm` files in
   `lib/` already comply with this constraint.

## Closing reference

If this question resurfaces — "should `class` be a builtin?" — the
answer is no, and the reason is Spinel. We are an AOT compiler making
the same tradeoff Spinel made: static class metadata over load-time
execution. The features that would force the latter (eval, dynamic
dispatch, define_method-analog) are explicitly out of scope.

## Sources

- [Spinel GitHub (matz/spinel)](https://github.com/matz/spinel)
- [Spinel HN thread](https://news.ycombinator.com/item?id=47887334)
- [An Overview of Spinel (Ruby Inside)](https://rubyinside.com/spinel/)
- [The Register: Ruby inventor Matz working on native compiler with
  AI help](https://www.theregister.com/devops/2026/05/06/ruby-inventor-matz-working-on-native-compiler-with-ai-help/5230532)
