# What is the SCOPE of a Sea-of-Nodes compilation? — prior-art research

**Date:** 2026-08-28
**Status:** research findings, primary-sourced
**Question owner:** T1 type-inference design (`docs/specs/2026-08-26-t1-type-inference-requirements.md` §2, `docs/plans/2026-08-26-t1-architecture-plan.md` L802)

## The question

Chalk's frontend (`B::SoN`) walks every CV the perl interpreter has loaded and
serializes them all. MEASURED: `my $x = 1 + 2; print $x` yields **412 graphs
across 116 packages** — `JSON::PP` (48), `Carp`, `warnings`, producer internals.
Exactly ONE graph is the program: `main::__PROGRAM__`.

T1's contract is `run($graph) -> $graph`. The spec forbids `Map<String, Graph>`
in a public signature on the principle that "the program is reachable FROM the
graph" via call edges. T1 nonetheless delegates to passes wanting more than one
graph, and the ruling of 2026-08-27 was to give the MOP a **unit-level graph
registry** enumerating every graph in the wire.

The concern: enumerating "the unit" runs inference over `JSON::PP`'s
implementation, which is (a) not the program and (b) a plausible cause of a
measured >150x slowdown as more nodes become analysis-eligible.

**So: what do production SoN compilers actually scope a graph, and a run of
dataflow analysis, to?**

---

## Per-system findings

### 1. HotSpot C2 — one `Compile` = one method

`src/hotspot/share/opto/compile.hpp` (OpenJDK master), class-level comment:

> "This class defines a top-level Compiler invocation."

Fields:

| Field | Comment (verbatim) |
|---|---|
| `ciMethod* _method` | "The method being compiled" |
| `int _entry_bci` | "entry bci for osr methods" |
| `RootNode* _root` | "Unique root of compilation, or null after bail-out" |

**One `Compile` object, one `_method`, one `_root`.** The unit of compilation is
a single method. There is no C2 object owning a set of ideal graphs; there is a
compile *queue*, but each dequeued task constructs its own `Compile`.

Other code enters **only by inlining**, tracked as
`GrowableArray<CallGenerator*> _late_inlines` — "List of CallGenerators to be
revisited after main parsing has finished". Inlining is decided during parse
(`Compile::Compile` takes a `ciMethod*`, parses it, recursively inlines using
Class Hierarchy Analysis), and the inlined callee's nodes are merged into the
*same* `_root` graph. There is no linking of separate graphs.

Source: [compile.hpp, OpenJDK](https://github.com/openjdk/jdk/blob/master/src/hotspot/share/opto/compile.hpp)

### 2. The founding SoN paper (Click & Paleczny 1995) — subroutines are opaque

"A Simple Graph-Based Intermediate Representation", Click & Paleczny —
retrieved successfully from
`https://www.oracle.com/technetwork/java/javase/tech/c2-ir95-150110.pdf`
(WebFetch got 403; plain `curl` with a browser UA succeeded, 143 KB).

Scope is stated through the START node (§3, verbatim):

> "The START node produces the initial control as well as initial values for all
> incoming parameters, memory, and the I/O state. The START node is a classic
> multi-defining instruction, producing a large tuple."

"Incoming parameters" fixes the graph at **procedure scope**. And the critical
sentence for the Chalk question — how a non-inlined callee is handled (§3):

> "We treat subroutines like simple instructions that take in many values and
> return many values. Subroutines take in and return at least the control token,
> the STORE, and the I/O state. They also take in any input parameters and may
> return an additional result."

**A call is a NODE, not an edge into another graph.** The callee's graph is not
consulted; the call is an opaque operator with a signature. Grepping the whole
paper for "inlin" returns two hits, neither about interprocedural scope — the
1995 design does not consider cross-graph analysis part of the IR at all.

### 3. GraalVM / Graal — `StructuredGraph` per root method

`StructuredGraph.java` (oracle/graal master). Class javadoc:

> "A graph that contains at least one distinguished node: the start node. This
> node is the start of the control flow of the graph."

Scope is carried explicitly:

- `private final ResolvedJavaMethod rootMethod;`
- `public ResolvedJavaMethod method()` — "Gets the **root method** from which this graph was built."

And inlining is recorded *into the same graph object*:

- `private final List<ResolvedJavaMethod> methods;` — "Records the methods that were used while constructing this graph, one entry for each time a specific method is used."
- `getMethods()` — "Gets an unmodifiable view of the methods that were **inlined while constructing this graph**."
- `updateMethods(StructuredGraph other)` — merges another graph's method list in.

So the precise answer to "what is `StructuredGraph`'s scope": **one root method,
plus whatever was inlined into it**, with the inlined set recorded as
provenance. It is not one method in a pure sense, and it is not a container of
graphs — it is one *merged* graph with an audit trail.

**Non-inlined callee typing:** the return stamp comes from the method
*signature*, not from the callee's graph. In `BytecodeParser`, arguments are
popped per `target.getSignature().getParameterCount(true)` and the invoke's
result type derives from `target.getSignature()`. This is the same mechanism as
Click 1995: a declared signature substitutes for the callee's body.

Sources: [StructuredGraph.java](https://github.com/oracle/graal/blob/master/compiler/src/jdk.graal.compiler/src/jdk/graal/compiler/nodes/StructuredGraph.java), [BytecodeParser.java](https://github.com/oracle/graal/blob/master/compiler/src/org.graalvm.compiler.java/src/org/graalvm/compiler/java/BytecodeParser.java)

### 4. V8 TurboFan — and why they LEFT sea of nodes

The V8 team's own post ["Land ahoy: leaving the Sea of Nodes"](https://v8.dev/blog/leaving-the-sea-of-nodes)
is first-party and directly on point. Their stated reasons: SoN is "too
complex... too limited... Compiling is too slow."

Two findings matter for Chalk, both about **analysis cost scaling with node
count**:

> "Turbofan's Load Elimination phase has a bailout on large graphs to avoid
> taking too long to finish and consuming too much memory."

A production SoN compiler found its dataflow pass had to **give up** past a node
threshold. And after moving to a CFG IR, their load elimination was measured
"up to 190 times faster"; overall "compile time got divided by 2 compared to SoN."

**This is a measured, first-party instance of the exact failure mode the Chalk
>150x concern describes.** A SoN dataflow pass whose input grows without bound
does not degrade gracefully; the industry response was a bailout, then a
rewrite.

I could NOT find in this post an explicit statement that a TurboFan graph is one
function — the post discusses individual functions in its examples and mentions
inlining once (in the WebAssembly/JS cross-inlining context), but does not state
the scope rule outright. See UNVERIFIED.

### 5. libFirm — the one system WITH a program-level container

libFirm is the most interesting case because it is the closest thing to a
counterexample, and it still does not do what the registry proposal does.

`include/libfirm/irgraph.h`:
> "This struct contains all information about a procedure."

One `ir_graph` = one procedure. And `include/libfirm/irprog.h` **does** define a
program-level owner:

> "Entry point to the representation of a whole program"

holding "a list of all procedures", "a list of all types", a start-method
reference, with `get_irp_n_irgs()` / `get_irp_irg(pos)` enumerating every graph.

**So a unit-level registry exists in libFirm.** But what runs across it? The
optimization header `include/libfirm/irgopt.h` opens:

> "@brief Optimizations for a whole ir graph, **i.e., a procedure**."

and every single entry point in it takes one graph:
`local_optimize_graph(ir_graph *irg)`, `optimize_graph_df(ir_graph *irg)`,
`remove_unreachable_code(ir_graph *irg)`, `remove_bads(ir_graph *irg)`,
`remove_tuples(ir_graph *irg)`.

The program-level container is used for **call-graph estimation**, not for
running dataflow. `include/libfirm/cgana.h`:

> "Analyses a rough estimation of the possible call graph. Determines for each
> Call node the set of possibly called methods." ... "cgana() sets the
> callee_info_state of each graph and the program to consistent."
> "Implements roughly Static Class Hierarchy Analysis."

Its purpose is stated as enabling devirtualization: "Replace (Sel-method(Alloc))
by Address", "Replaces Sel-method by Address if the method is never overwritten."

**Verdict on libFirm: the registry exists, but it holds a WORK LIST and a
call-graph side table. Dataflow optimization is strictly per-`ir_graph`.** That
is precisely the distinction the Chalk question needs.

### 6. LLVM — the "registry of all graphs" shape, and its measured cost

LLVM is not SoN, but its `Module`-of-`Function`s with interprocedural passes is
structurally the registry proposal, so it is the strongest available
counterexample. The first-party
[LLVM blog on ThinLTO](https://blog.llvm.org/2016/06/thinlto-scalable-and-incremental-lto.html):

Full/monolithic LTO:
> "The LLVM implementation loads all input bitcode files and merges them
> together to produce a single Module."

The consequence, stated by the implementers:
> "LTO often requires a large amount of memory (to hold all IR at once) and is
> very slow."

The fix was **not** a better registry — it was to stop merging and substitute
**summaries**:
> "a function is abstracted with its linkage type, the number of instructions it
> contains, and optional profiling information (PGO). Additionally, every
> reference (address taken, direct call) to another global is recorded."

and to import selectively: "only those functions likely to be inlined are
imported into each module."

**So: "put every function in one container and run interprocedural analysis over
it" was TRIED at industrial scale, measurably failed to scale in time and
memory, and was replaced by per-unit compilation plus compact summaries.**

---

## The AOT section (the most important one)

The three JITs above pick a root because it got hot, and they have profiles.
Chalk is AOT with no profile. The question is whether AOT changes the answer to
"enumerate everything?"

**It does not. AOT compilers universally start from declared ROOTS and traverse.**

### GraalVM Native Image — closed world by reachability, not by enumeration

Native Image uses the *same* Graal IR, so it is the closest analogue to Chalk:
AOT, SoN, no profile.

The closed-world assumption, per [Native Image Basics](https://www.graalvm.org/latest/reference-manual/native-image/basics/):
> "Once a native image is built, no new elements can be added at run time, for
> example, through class loading."

But closed-world does **not** mean "compile everything on the classpath". The
mechanism is reachability from roots:

> "It starts from the entry points of the application (the `main` method)."
> "Only **reachable** elements are included in the final image."
> ...iterating "until further scanning yields no additional changes in element's reachability."

Verified in source. `PointsToAnalysis.java` (oracle/graal master) exposes an
explicit root-registration API:

- `addRootMethod(Executable method, boolean invokeSpecial, Object reason, ...)`
- `addRootMethod(AnalysisMethod aMethod, ...)` → `registerAsDirectRootMethod(reason)` / `registerAsVirtualRootMethod(reason)`
- `addRootClass(Class<?> clazz, boolean addFields, boolean addArrayClass)`
- `forcedAddRootMethod(...)`

and a fixed-point driver: `finish()` → `universe.runAtFixedPoint()`, with
`validateFixedPointState()`.

Note `addRootMethod` takes a **`reason`** parameter — roots are justified and
attributable, not ambient.

**Crucially, graph construction is LAZY and reachability-driven.**
`MethodTypeFlowBuilder.java` holds `protected StructuredGraph graph;` (one
graph, one method) and builds it via `private boolean parse(Object reason,
boolean forceReparse)` — again carrying a *reason*. A method's graph is parsed
**because it was proven reachable**, not because it was on the classpath. The
JDK is on the classpath of every Native Image build; Native Image does not build
a `StructuredGraph` for all of it.

The [Static Analysis Reports docs](https://www.graalvm.org/latest/reference-manual/native-image/debugging-and-diagnostics/StaticAnalysisReports/)
confirm the shape: the call tree is "a breadth-first tree reduction of the call
graph as seen by the points-to analysis"; the analysis "eliminates calls to
methods that it determines cannot be reachable at runtime" and "completely
eliminates invocations in unreachable code blocks." Reachability reports exist
specifically to answer *why* a given element is reachable — i.e. the path from a
root. Dynamic features (reflection) are handled by **explicitly declaring extra
roots** in metadata, not by falling back to enumerating everything.

### libFirm (AOT C compiler)

Covered above: per-procedure graphs, per-procedure optimization, program
container used for call-graph estimation. Interprocedural info flows via
`cgana()`'s callee sets attached to Call nodes — i.e. **a side table keyed by
call site**, not by running dataflow over a merged graph.

### LLVM / ThinLTO (AOT, whole-program)

Covered above. The AOT whole-program compiler that *did* enumerate everything
into one container is the one that had to be redesigned around summaries.

### Direct answer: is "enumerate every function you can see" ever the right AOT answer?

**No source found supports it.** Every AOT system examined starts from declared
roots and traverses:

- Native Image: `addRootMethod` / `addRootClass` + fixed-point reachability; lazy per-method graph parsing gated on a `reason`.
- LLVM: entry points and symbol liveness; ThinLTO explicitly avoids materializing all IR.
- libFirm: per-procedure optimization; program list is a work list.

The closest thing to "enumerate everything" is monolithic LTO, and its own
authors describe it as "very slow" with "a large amount of memory", and replaced
it.

---

## Comparison table

| System | AOT/JIT | Graph scope | How other code enters | Unit-level container? | What runs across the container | Non-inlined callee type |
|---|---|---|---|---|---|---|
| Click/Paleczny 1995 | — | One procedure (START yields params) | not addressed | No | — | Call is an **opaque instruction** with a signature |
| HotSpot C2 | JIT | One `_method`, one `_root` | Inlining only (parse-time + `_late_inlines`), merged into same graph | No (compile queue only) | — | Signature + profile/CHA |
| Graal | JIT | `rootMethod` **plus inlined callees**, inlined set recorded in `methods` | Inlining (merged), snippets/intrinsics | No | — | Stamp from `target.getSignature()` |
| TurboFan | JIT | function (not explicitly stated in source found) | Inlining | Not found | — | not verified |
| libFirm | AOT | One `ir_graph` = "all information about a procedure" | Inlining | **YES** — `ir_prog`, "whole program", enumerable | Call-graph estimation (`cgana`, ~CHA) — **NOT dataflow**; all of `irgopt.h` is per-`irg` | `cgana()` callee sets on the Call node |
| Native Image | **AOT, SoN, no profile** | One `StructuredGraph` per method, **parsed lazily on reachability** | Inlining; reachability adds new methods | Analysis universe, built by traversal | Points-to fixed point over *reachable* set only | Type-flow through call, from reachable callees |
| LLVM full LTO | AOT | Function; all merged into one `Module` | Merging | **YES** — the failure case | Interprocedural passes; "very slow", "large amount of memory" | Callee IR present (that's the cost) |
| LLVM ThinLTO | AOT | Function; per-module | Selective **importing** of likely-inlined functions | Summary index (**not** IR) | Summary-based IPO | **Module summary** |

---

## What this implies for a compiler in chalk's position

1. **The `run($graph) -> $graph` contract matches every system examined.** C2
   (`Compile`/`_method`), Graal (`StructuredGraph`/`rootMethod`), libFirm
   (`local_optimize_graph(ir_graph*)`) all take exactly one graph. The spec's
   §2 instinct is well-supported prior art, not an idiosyncrasy.

2. **A unit-level registry has precedent — but ONLY as a work list / call-graph
   side table, never as dataflow input.** libFirm is the proof of both halves:
   `ir_prog` enumerates every graph, *and* every optimization in `irgopt.h`
   takes a single `irg`. The registry idea is therefore not automatically an
   anti-pattern. **What determines which it is: whether analysis iterates the
   registry, or whether the registry only answers point lookups reached through
   an edge.** A registry used as "resolve this callee reference" is libFirm's
   `cgana`. A registry used as "for each graph in the unit, run T1" is
   monolithic LTO.

3. **Reachability, not enumeration, is the AOT filter — and it is what makes
   Native Image's cost survivable.** Native Image's own JDK-on-classpath problem
   is structurally identical to Chalk's `JSON::PP`-in-the-wire problem: the
   producer makes far more code visible than belongs to the program. Its answer
   is `addRootMethod` + fixed point + lazy `parse(reason)`. Applied to Chalk:
   the root is `main::__PROGRAM__`; the other 411 graphs enter only if a call
   edge proves them reachable. On the measured two-line program, the reachable
   set from `__PROGRAM__` is a tiny fraction of 412.

4. **The >150x concern has a first-party precedent, and it is not hypothetical.**
   V8 shipped a *bailout* on large graphs in Load Elimination, then left SoN
   entirely, citing compile time; their CFG replacement measured up to 190x
   faster on that same pass. A SoN dataflow pass fed an unbounded node count is
   a known-bad configuration.

5. **Typing a call without the callee's graph is the ORIGINAL SoN design, not a
   compromise.** Click 1995: "We treat subroutines like simple instructions that
   take in many values and return many values." Graal: stamp from
   `target.getSignature()`. libFirm: `cgana()` callee sets. LLVM ThinLTO: module
   summaries. **Every system has a summary mechanism precisely so that dataflow
   does not need the callee's body.** If Chalk's Call nodes carry a return
   stamp (from the wire's declared types, or a computed summary), T1 needs no
   registry for typing at all — which is exactly what spec §2 asserts.

6. **The distinction the ruling should turn on** is not "registry vs no
   registry" but "**pull vs push**": is a foreign graph fetched because an edge
   in the graph under analysis demanded it (libFirm/Native Image — fine), or is
   the pass driven by iterating the container (full LTO — the measured failure)?
   The registry attached to the MOP is defensible in the first shape. The risk
   is that the `transforms => sub ($graphs,$mop)` slot flagged in
   `docs/plans/2026-08-26-slice4-build-verification.md` L63 is the second shape,
   which is where the >150x lives.

---

## UNVERIFIED — what I could NOT confirm

Stated explicitly, not smoothed over:

1. **Cliff Click's PhD thesis is unreachable.** As warned. Probed
   `https://scholarship.rice.edu/handle/1911/96451` → HTTP 202 with zero bytes;
   `https://scholarship.rice.edu/bitstream/handle/1911/96451/TR95-252.pdf` → 202,
   zero bytes; two other mirrors → 404. **Nothing in this document is sourced
   from the thesis.** The 1995 Click & Paleczny IR paper WAS retrieved and is
   quoted; the thesis's treatment of global code motion / CCP scope is not
   covered here.

2. **TurboFan's graph scope is NOT verified from source.** I confirmed the V8
   team's stated reasons for leaving SoN and the Load Elimination bailout, both
   first-party. I did **not** find a primary statement that a TurboFan
   sea-of-nodes graph is scoped to one function plus inlinees, and I did not
   read `JSGraph`/`JSInliner` source. Treat the TurboFan row as partially
   evidenced. The claim I *do* stand behind for TurboFan is the analysis-cost
   one, which is quoted directly.

3. **The Wimmer et al. OOPSLA 2019 paper ("Initialize Once, Start Fast") was
   NOT read.** `christianwimmer.at` → ECONNREFUSED; ACM DL → 403; ResearchGate →
   403. The Native Image findings here come from **Graal source
   (`PointsToAnalysis.java`, `MethodTypeFlowBuilder.java`) and official GraalVM
   docs**, which I consider adequate and arguably better primary sources for the
   mechanism. But the paper's own framing of the iterative
   points-to + heap-snapshotting fixed point is quoted only as reported by
   search-result summaries, so I have **not** relied on it for any claim above.

4. **The VMIL 2021 keynote paper ("GraalVM Native Image: Large-scale static
   analysis for Java") was not retrieved** (ACM DL). Same mitigation as above.

5. **Graal's `BytecodeParser` non-inlined-invoke stamp path was read via a
   summarizing fetch, not by me line-by-line.** The direction (signature-derived
   return type) is consistent with Click 1995 and with `StampFactory` naming,
   and I regard it as reliable, but I did not personally read
   `createNonInlinedInvoke` / the exact `StampFactory.forDeclaredType` call site.
   Flagging it as one confidence level below the `StructuredGraph` and
   `compile.hpp` findings, which I quote from directly-fetched source.

6. **I did not measure anything in Chalk.** The 412-graphs/116-packages figure
   and the >150x slowdown are taken as given from the task brief. This document
   is prior art only; it does not verify Chalk's own numbers.

7. **No source was found either supporting or refuting "enumerate everything you
   can see" as a deliberate AOT strategy.** My finding is an absence: every AOT
   system I could source starts from roots. Absence of evidence is reported here
   as absence, not as proof of impossibility.
