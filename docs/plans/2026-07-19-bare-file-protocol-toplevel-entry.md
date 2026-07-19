# Bare-file protocol: the top-level program root as the implicit entry

**Status:** DESIGN NOTE (2026-07-19, perigrin). No code yet. Orthogonal to the
runtime-MOP design (`2026-07-19-runtime-mop-coerce-multimethod.md`); this is about
the PROGRAM's control entry, not the metalayer.

## The problem (measured)

C/Rust/Java/Go execute from a NAMED entry (`main`); a file's top level is only
declarations. **Perl (and Chalk should match) has NO `main`** — a file RUNS
top-to-bottom; the top-level statements ARE the program. `perl foo.pl` executes
`PL_main_root` (the compiled top-level optree) directly; `sub`s are just
definitions encountered along the way.

Today's pipeline models Perl as if it were C:
- B::SoN's `_discover_and_translate` walks package STASHES and translates CVs
  (subs) ONLY. It NEVER touches `main_root` (the top-level program optree).
- MEASURED: a bare file (`my $x=1; print "hi\n"; $x+1`) emits `methods: {}` —
  the top-level program produces NO GRAPH. Nothing to run.
- The drain harness fakes an entry by wrapping the whole file in `sub __main__
  { ... }` (`t/lib/Chalk/CodeGen/Harness/MainWrap.pm`). This is a LIE that works
  for straight-line driver code but: (a) top-level `sub foo {...}` becomes a
  NESTED sub (the lex.t/subval.t wall), and (b) a genuinely bare file has nothing.

**LOAD-BEARING CLARIFICATION (perigrin's question, verified): B::SoN CANNOT
compile a bare Perl file AT ALL.** None of the t/base files are scoped to a
package stash of CVs, so the CV-walker finds nothing. The ONLY reason any t/-drain
works is that `Mode1Runner::_lower_wrapped` TEXTUALLY REWRITES every file first:
`"package main;\n" . wrap_main($body)` where `wrap_main = "sub __main__ {\n$body\n}\n"`.
The file's top-level statements are literally MOVED INSIDE a synthetic
`sub __main__`, becoming a CV the walker can find (the harness then reads
`$data->{methods}{'main::__main__'}`). So EVERY drain so far (if.t/cond.t/elsif.t)
ran through this source-text wrap — a preprocessor hack (same KIND of thing as the
archive heredoc preprocessor) papering over a producer gap. The wrap is 100%
load-bearing and it is a SCAFFOLD. This design replaces the text-rewrite with the
real mechanism (walk `main_root`), so no rewrite is needed and top-level subs
become sibling CVs instead of being mangled by the wrap.

## The key measurement: `main_root` is a real optree, subs are separate

`B::main_root()` / `B::main_start()` DO expose the top-level program optree.
`perl -MO=Concise,-main` on `my $x=1; print "hi\n"; sub foo {42} $x+foo()` shows:

```
main program:
  leave[1 ref] -> enter                      (the program root; enter..leave)
    nextstate; padsv_store[$x] <- const 1    (my $x = 1)
    nextstate; print "hi\n"
    nextstate; add( padsv[$x], entersub( gv[\&main::foo] ) )   ($x + foo())
```

CRITICAL: **`foo`'s body (`42`) is NOT in this tree** — it's a separate CV. The
top-level program CALLS it via `entersub -> gv[\&main::foo]`. So perl ALREADY
represents a file as: `{top-level program root}` + `{sub CVs}`, where the program
root CALLS the subs. The split we need already exists in perl's own model.

## The fix — the top-level root is a compilation unit; START wires into it

Same IR shape we already lower (Start -> control chain -> exit); the ONLY missing
thing is that the producer points that machinery at CVs and must ALSO point it at
`main_root`.

1. **Producer (B::SoN `_discover_and_translate`):** translate `main_root` into a
   graph — `main::__PROGRAM__` — with the SAME FromOptree walker used for CV
   bodies. The tree's `enter -> statements -> leave` maps to `Start -> control
   chain -> exit` exactly like a method body. This is the IMPLICIT entry; no
   `main` symbol needed because the file root IS the entry.
   ```perl
   # alongside _walk_package(..., 'main', \%main::, ...):
   my $root = B::main_root; my $start = B::main_start;
   $graphs{'main::__PROGRAM__'} = _translate_root($root, $start, ...) if $$root;
   ```
2. **START wiring (the literal question):** the `__PROGRAM__` graph gets a `Start`;
   top-level statements thread the control chain from `Start` in program order
   (the EXISTING effect-by-default + Print-threading mechanism, already proven by
   how the harness `__main__` works). A top-level `entersub` -> a `Call` node
   referencing the callee sub graph. **[ASSESS3 G1 — this is a THIRD work item, NOT
   "already handled." The current inter-graph mechanism (`_lower_call_direct` +
   F5/F8 arg-binding) INLINES ONLY (no `define`+`call`; the callee's own comment says
   real call emission is F3, unbuilt), lowers ONLY a SINGLE-Return VALUE subgraph, and
   SILENTLY DROPS effectful callee bodies (the default-pure effect-drop class). The
   runtime-MOP doc's pilot sequence calls this same machinery "the pilot's biggest
   UNPROVEN mechanism" (F10). So a top-level program calling an effectful/multi-return
   sub — the NORMAL shape in lex.t/subval.t — needs either effect-aware inlining or
   true `define`+`call` emission BUILT. See §EFFORT SPLIT correction below.]** Program
   fall-off-the-end / explicit `exit` -> the entry graph's exit -> `ret`.
3. **Backend:** the `__PROGRAM__` graph IS `define i32 @main()` — Perl's top-level
   root lowered directly as the LLVM entry (or the XS BOOT for that target). The
   C-world `main` and Perl's top-level root are the SAME IR node (`Start` -> chain
   -> exit); the difference is purely at the PRODUCER (C names it `main`; Perl's
   is the anonymous file root discovered from `main_root`).
4. **Delete `MainWrap.pm`:** the producer emits the real `__PROGRAM__`; the harness
   stops faking `sub __main__`.

## EFFORT SPLIT (measured 2026-07-19; CORRECTED 2026-07-19 ASSESS3): producer + backend + a THIRD item (inter-graph calls)

**[ASSESS3 G1: the original "~90% producer, ~10% backend" was NOT defensible.** It is
right that the ENTRY mechanism is lopsided (walking main_root is the bulk; feeding a
Return-rooted graph to `lower` is trivial). But it UNDERCOUNTED a THIRD line item:
inter-graph CALLS. A real file = `__PROGRAM__` + N sub graphs the program CALLS, and
for effectful/multi-return subs (the lex.t/subval.t targets) the current inliner drops
effects or GAPs. So the honest split is: (1) ENTRY producer work (~big, walk
main_root), (2) ENTRY backend work (~small, feed the graph), (3) INTER-GRAPH CALL work
(unbudgeted — effect-aware inlining OR true `define`+`call`, shared with the
runtime-MOP pilot's F10). Item 3 is the risk, not a rounding error.]**

The ENTRY ends are lopsided because **Chalk's backend was NEVER actually C-like** —
it does not require a named entry; it treats ANY graph as "the program starting at
Start." The C-like assumption lives ENTIRELY in the producer (walks CVs, ignores
main_root) + the harness (fakes a CV).

**End 1 — Producer (B::SoN): ~90%, the real work.** Teach `_discover_and_translate`
(which SHOULD be renamed `coerce(OPTree, SoNGraph)` — it is a MOP coercion between
representation types, uniform with `coerce(Int,Str)`; see the runtime-MOP doc's
"coerce spans representation types" section; `B::SoN` IS gen-0's this coercion) to
translate `main_root` → `main::__PROGRAM__`. The genuinely-new piece: a CV body
ends in `leavesub`; the main root ends in `leave` (the program's outermost scope,
context = the process, not a caller). The walker's sub-exit handling
(leavesub/return → the graph's Return) needs a MAIN-ROOT VARIANT (top-level
`leave` → the program's Return/exit). Everything else (op vocabulary, control
threading, implicit Return, inter-graph Calls) is the existing machinery.

**End 2 — Backend ENTRY wiring (Chalk): ~small, mostly ALREADY DONE** (the ENTRY end
only — inter-graph CALLS are the separate THIRD item per G1 above, NOT counted here).
MEASURED: `Chalk::Target::LLVM->lower($return_node)` takes ANY Return-rooted graph and
emits `define i32 @main()` with the control chain threaded from entry — agnostic to
whether the graph came from the wrap or main_root. Even a no-explicit-return body
gets an implicit Return (`Return(Print)` for `print "hi\n"`), so the graph shape
is uniform. What is actually new on this end:
- feed it `__PROGRAM__` instead of `__main__` (one-word change; harness reads
  `methods{'main::__main__'}` today → `__PROGRAM__`). Trivial.
- EXIT SEMANTICS: today the graph's Return value becomes the drain harness's
  `Int:`/`Str:` type-tag. For a REAL executable, the top-level Return maps to
  PROCESS EXIT STATUS (`ret i32 <status>`), and mid-program `exit(N)`/`die` → the
  `@exit(N)` machinery (die already does this). A small semantics decision, not
  new machinery.
- MULTIPLE UNITS: `lower` takes ONE graph today. A real file = `__PROGRAM__` + N
  sub graphs. **[ASSESS3 G1 — this is the THIRD line item, NOT "already emits."** The
  backend INLINES a referenced sub graph via `resolved_graph`, but only a single-Return
  VALUE subgraph, and DROPS effectful bodies; the non-inlined true `define`+`call` case
  DOES NOT EXIST (F3, unbuilt). This is real work, shared with the runtime-MOP pilot's
  F10 (prove the inliner on a loop+effect callee), not a confirmation task.]**

So "fix Chalk to start at program start" is MOSTLY ALREADY TRUE; the real fix is
"fix B::SoN to hand Chalk the program's actual root graph."

## Why this ALSO fixes the top-level-subs problem (same fix)

The bare-file protocol and the top-level-sub problem are ONE fix. A file is
`{__PROGRAM__ from main_root}` + `{sub graphs from CVs}`, program graph CALLS the
sub graphs. `main_root` NATURALLY excludes sub bodies (separate CVs) — so walking
`main_root` AND the CVs, and letting `__PROGRAM__`'s Call nodes reference the sub
graphs, is exactly perl's model. Subs stop being NESTED inside a wrap (`__main__`'s
lie) and become SIBLING compilation units the program calls. This unblocks
lex.t/subval.t/arith.t/... (all the "defines top-level subs" files the current
single-sub wrap mangles).

## Why this is a self-hosting-lib/ prerequisite

A `.pm` file's top level (`package`, `use`, `field` init, `our` decls) RUNS at
LOAD time — same `main_root` question. Compiling `lib/` through Chalk needs the
top-level/load-time execution modeled, not just the method CVs. So the bare-file
protocol is on the path to the lib/ capstone (019f5da9 / 019eaa51), not just a
t/-drain convenience.

## Open questions

- **BEGIN/END/INIT blocks** and `use` at the top level are COMPILE-TIME effects
  the optree has already partly executed/folded; decide what `__PROGRAM__` should
  contain (runtime top-level only?) vs what is already resolved at parse.
- **Exit semantics:** Perl's top-level "return" is process exit status / falling
  off the end; map to `ret i32` from `@main`. `exit(N)` mid-program -> the Unwind
  / exit machinery (die already lowers to `@exit`).
- **Multiple packages in one file** (`package Foo; ...; package Bar; ...` at top
  level) — the top-level statements span package switches; `__PROGRAM__` is still
  one control chain but the stash context changes. Model the `package` op.
- **Ordering vs CV discovery:** subs are defined at compile time (CV exists before
  `__PROGRAM__` runs), so `__PROGRAM__`'s Calls can reference sub graphs
  regardless of textual order — but confirm the producer emits both and links
  them (the existing `resolved_graph` mechanism should extend).
