# The loader only loads: whole-program policy moves to passes

**Date:** 2026-11-13
**Status:** PLAN. Not started.
**Follows:** `2026-08-24-loader-analysis-pipeline.md` (which moved the typing
analyses out of the deserializer into `Chalk::IR::Analysis`).
**Origin:** perigrin, on the SubDefined work --

> Probably shouldn't be the loader it should be an optimization pass
>
> The loader also shouldn't be pruning that should probably also be an
> optimization pass
>
> [building a graph can itself fail on an op the loader can't handle yet]
> This suggests again that the loader is doing way too much work

## The problem, as found

`from_json` (lib/Chalk/IR/Serialize/JSON.pm) turns the wire into nodes -- and
also decides, before or while building them, what the program is. Measured
2026-11-13:

| In the loader today | What it is |
|---|---|
| `_reachable_methods` on the raw JSON, then `delete @{ $data->{methods} }{@gone}` | reach analysis + dead-code elimination |
| `die "GAP: $runs, which the program calls, is refused in its module"` | a refusal decided by reach |
| BEGIN/END classification: `@PHASE_BLOCKS`, `%USED_MODULES`, `die "GAP: a $phase block with effects of its own"` | phase classification (the future BEGIN evaluation) |
| `%CONTEXT_COPY` / `%CONTEXT_COPY_EVAL`: a sub's wire graph deserialized again per caller context | a transform: specialisation by context |
| `$STASH_CHANGES`, `%PROTOTYPES`, `%FOLLOWED`, `%CODE_GRAPHS`, `$DATA_SECTION` | program facts, held in package globals |
| `%RUN`, `%ON_WIRE`, `%REFUSED`, `%REFUSED_CALLED` (added 2026-11-13 for SubDefined) | the same pattern, repeated -- reach shared with a pass through globals |
| `Chalk::IR::Analysis->run(...)` at its end | the pipeline, called from the deserializer (the 08-24 plan's open item; `loader-reproduces-the-wire.t` measures what it adds) |

Two consequences:

1. **Reach is computed on strings.** It runs before nodes exist, so it matches
   calls by name: no call targets, no class resolution. So it counts every one
   of the program's own subs as running, because they are all loaded --
   SubDefined then refuses `defined &nope` because some never-called
   `main::f` holds an eval.
2. **Pruning protects the program from the loader.** The deeper reason pruning
   runs before deserialization: building a graph can fail (an op the loader
   cannot build yet), and pruning first kept a broken, never-called module sub
   from refusing a program that does not use it. The loader is fragile, so
   policy was put in front of it.

The remaining `die`s while building a node (PadAccess or EntryDef with no
sigil, an eval entry out of order) are a different thing: a MALFORMED WIRE.
They are right to stop the load, but they are not GAPs (a GAP is "a valid
program, not lowered yet") and should say so.

## The target

**The loader:** JSON -> a program object, nothing else.

- Every graph on the wire, built. Never pruned.
- An op it has no class for becomes a generic node holding its op name and
  fields. It still loads; a pass, or the backend, refuses it by name only if it
  is reached.
- The wire's metadata kept on the object, not in globals: `refused`, followed
  modules, phase blocks, stash, prototypes, data section, classes.
- A malformed wire is a hard error, worded as one ("malformed wire: ..."), not a GAP.
- It does not call Analysis.

**The pipeline:** passes over that object, each reading and writing it, in
order:

1. **Reach** -- sure / maybe, over real graphs: direct calls by target, method
   calls through the class chain, a method on an unknown invocant as maybe,
   lifted bodies, `can` by a known name. The program's own subs are reached
   only if something reaches them (main, phase blocks, a reference taken).
2. **Refuse** -- a sure reach of a refused module sub or of a generic node:
   the program is refused, in that sub's words.
3. **Prune** -- unreached graphs leave the program.
4. **Phases** -- BEGIN/END classified (later: evaluated at compile time, see
   below).
5. **Context copies** -- a sub whose value depends on its caller's context gets
   a copy per context, as a graph-to-graph transform.
6. **SubDefined** -- `defined &NAME` answered from reach (pass 1), or refused
   naming the graph that may change it.
7. **The existing Analysis passes**, unchanged.

Each pass is a function `(program) -> program`, or one that dies with a GAP.
The globals go; a consumer that read `%Chalk::IR::Serialize::JSON::CODE_GRAPHS`
reads the program object.

## Why this order of steps

Each step lands green on its own (producer suite, chalk suite vs base,
census, corpus gates), and keeps every existing caller of `from_json`
working until the last one.

1. **Program object.** `from_json` returns the same graphs as now, plus an
   object carrying the metadata. The globals stay, filled from it, so nothing
   moves yet. Test: the object holds what the wire sent.
2. **Malformed wire is not a GAP.** Reword the three node-level `die`s. Test:
   each reports "malformed wire".
3. **Generic node for an op with no class.** Test: a wire with an invented op
   in an unreached module sub loads; reached, it is refused by name.
4. **Build everything, then reach / refuse / prune as passes** (passes 1-3).
   This is the step that needs 3: with nothing pruned first, a sub that cannot
   be built must not refuse the program. Tests: the existing reach tests
   (sure refuses, maybe does not, Exporter pruned); NEW: a program's own sub
   that nothing calls is not reached (`sub f { eval $x } print defined &nope`
   answers instead of refusing -- t2-defined-sub-asked-where-it-runs.t gains
   the case it had to drop).
5. **SubDefined reads the program's reach**, not loader globals (`%RUN` etc.
   go).
6. **Phases** and 7. **context copies** move out, one change each.
8. **`from_json` stops calling Analysis**; callers that want an analysed
   program call the pipeline. `loader-reproduces-the-wire.t` reaches zero
   added stamps -- the 08-24 plan's definition of done.

## Costs and risks

- **Building every module sub.** POSIX alone is hundreds of subs, today never
  built. Unmeasured. Measure load time on the census before and after step 4;
  if it matters, the loader can build lazily (a graph built when a pass first
  asks for it) without putting policy back in the loader.
- **Reach on real graphs can be MORE permissive than on strings** (the
  program's own uncalled subs stop counting). Every place that relied on "all
  program subs run" must be found: a computed call (`&{"f"}`, `$code->()`
  without a known target) must make every sub it could name reachable, or
  refuse. Test it before relying on it.
- **Order dependencies hidden in from_json.** Context copies are made after
  pruning and before Analysis, and some later code reads `%CONTEXT_COPY`.
  Each move is its own step so a broken dependency shows up alone.

## Related, later

**BEGIN as compile-time evaluation** (perigrin, same discussion: "This feels
like the answer to BEGIN phasers entirely … they get evaluated during the
lowering functor or possibly during an optimization pass"). With phases as a
pass (step 6), a BEGIN graph can be partially evaluated: what its inputs fix at
compile time (imports, `@ISA`, `our` values, `use constant`) folds into the
program's initial state; what touches the world (`print`, `chdir`, `-d`,
`%ENV`, `time`) stays a run-time prologue in order -- the same rule as
SubDefined: fold only what cannot differ between build and run. Needs a SoN
graph interpreter (which constant folding wants too) and an initial-state
image T2 can emit. Its own plan.
