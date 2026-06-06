# CodeGen Harness — Architecture Review (READ-ONLY / diagnosis)

Date: 2026-06-06
Branch: phase1-lateral-bindings
Reviewer: principal-engineer architecture pass
Scope: the codegen-harness as a SYSTEM (trust root, coupling, false-green
surfaces, maintainability). Diagnosis only — no fixes proposed.

System under review (verified state):
- 7 harness modules (Harness.pm + 6 under Harness/), 1 new IR node (ListAssign),
  35 test files under t/bootstrap/codegen-harness/.
- Verified live: gap-map generate() -> denominator 78, PASS 76, DEFERRED 1 (M20),
  REJECT 1 (M21), tier1_green() == TRUE. All 35 test files pass.

---

## EXECUTIVE SUMMARY

The harness is a well-conceived instrument. Its cardinal design choice — the
oracle (RunUnderPerl) runs the raw corpus snippet under stock perl with ZERO
Chalk-compiler dependency — is correctly implemented and is the single most
important thing to protect. The gap-vs-miscompile classifier is sound and the
emission_meta-decides-first ordering correctly prevents an incomplete emission
from being laundered as PASS.

However, the trust root has THREE concrete cracks, two of which I confirmed
empirically:

1. HIGH — the dual source-of-truth for corpus snippets has ALREADY DRIFTED.
   Harness.pm's in-module %CORPUS and the on-disk t/fixtures/ir-audit-corpus.pl
   disagree on F3 (and the file has M20/M21 the module lacks). Two entry points
   (run_entry vs GapMap) feed the oracle DIFFERENT source for the same tag.
2. HIGH (latent) — the documented FP-tolerance axis is effectively dead code in
   production. The oracle always emits dualvar_policy 'numeric-first', but the
   Comparator only branches on 'numeric'/'string'; 'numeric-first' falls to the
   exact-string default. Confirmed by direct test. Currently fails-safe
   (conservative MISCOMPILE, not false-green) but the instrument does not do
   what its own docs claim.
3. MED — 2 of the 10 advertised BehaviorRecord axes (object_state,
   aliasing_topology) are NEVER populated by the oracle (always {}). The record
   advertises observability it does not deliver; a pure-field-mutation idiom
   would be invisible. No such idiom exists in tier-1, so latent, not active.

HandGraphs.pm at 4016 lines is NOT a god-file problem in the maintainability
sense (it is flat, append-only fixture data with a clean dispatch table) but it
IS carrying ~57x duplicated construction boilerplate that should be factored
before it grows. GapMap.pm is borderline god-object: verdict-registries +
green-definition + exercise-specs + generator + artifact I/O in one module. See
ranked findings.

---

## STRENGTHS (protect these)

S1. ORACLE INDEPENDENCE IS REAL (the trust root holds).
    RunUnderPerl.pm imports only Carp/File::Temp/JSON::PP/Scalar::Util/
    IPC::Open3/Symbol + the pure-data BehaviorRecord. The wrapped driver program
    (RunUnderPerl.pm:117-218, 338-397) references zero Chalk modules and runs the
    snippet under $PERL_BIN with only core pragmas. The oracle cannot be fooled
    by a compiler bug because the compiler is not in its path. This is the
    correct architecture and the highest-value invariant in the system.

S2. NO-JSON HAND GRAPHS (no lossy round-trip in the P path).
    HandGraphs builds Chalk::MOP node-by-node via NodeFactory; never through
    from_json. hand-graphs-neg.t N1 actively guards this by overriding
    Chalk::IR::Serialize::JSON::from_json and asserting it is never called.
    The P side therefore tests the live emitter against an authored graph, not a
    serialized approximation.

S3. GAP-vs-MISCOMPILE CLASSIFIER IS SOUND (Comparator.pm:38-122).
    emission_meta is checked FIRST (lines 44-50): marked_unsupported OR
    !emitted_for_every_construct => GAP, before any axis comparison. A complete
    emission that diverges on any axis => MISCOMPILE (lines 107-116). The
    directional framing genuinely cannot launder a miscompile as a gap. This is
    the load-bearing discrimination and it is implemented exactly as documented.

S4. EMPTY-RECORD COLLUSION GUARD (Comparator.pm:56-63).
    Two degenerate records (no rv/stdout/stderr/exception/state) yield MISCOMPILE
    with implicated_layer 'oracle', not a vacuous PASS. Correct: agreement on
    nothing is not evidence of correctness.

S5. DEFERRED/REJECT are registry-gated, not free verdicts (GapMap.pm:33-57,
    180-196). tier1_green skips only verdicts REJECT/DEFERRED, and those only
    come from the explicit %REJECT_IDIOMS / %DEFERRED_REASONS tables. An ordinary
    NOT-YET-COVERED still blocks green. DEFERRED is not a loophole.

S6. ListAssign IR node is CONVENTION-CONSISTENT, not a one-off.
    ListAssign.pm content_hash() returns id() (per-position identity), mirroring
    VarDecl.pm:20-22 verbatim. NodeFactory registers it in @DATA_CLASSES and gives
    it a dedicated counter-suffixed, hash-cons-excluded branch
    (NodeFactory.pm:96, 239-244) exactly parallel to the VarDecl branch (229-234).
    No ripple risk to the broader IR; it follows the established statement-position
    side-effect-node pattern.

S7. _emit_mop_adjust is a clean, targeted addition (Perl.pm:203-209).
    It uses the same %_aggregate_vars save / _scope_body_vars_mop / scheduled-body
    / restore sequence as _emit_mop_method (Perl.pm:214-224). Not special-case
    accretion — it reuses the existing method-emission machinery with an empty
    params list, which is the correct framing for an ADJUST phaser.

---

## FLAWS / RISKS (ranked)

### HIGH

H1. DUAL SOURCE-OF-TRUTH FOR CORPUS SNIPPETS — ALREADY DRIFTED.  [FALSE-GREEN SURFACE]
    Evidence: Harness.pm:18-95 hardcodes %CORPUS; GapMap.pm:17,231-239 reads
    t/fixtures/ir-audit-corpus.pl. I diffed them programmatically:
      - F3 DIVERGES: module has `sub foo { return $_[0]+$_[1] } method m()...`;
        the corpus FILE has only `method m() { my $r = foo(1,2); return $r; }`
        (no foo definition — the file snippet would die "Undefined subroutine
        &C::foo" if run as the oracle source).
      - M20, M21 exist ONLY in the file (the module table omits them).
    Two entry points consume different sources: Harness::run_entry (used by
    wire.t) feeds the oracle from %CORPUS; GapMap::_run_one feeds it from the
    file. The SAME tag can therefore be exercised against TWO DIFFERENT snippets
    depending on which driver runs.
    Impact: the oracle's "source of truth" is forked. A snippet can be fixed in
    one source and stay wrong in the other; a gap-map PASS does not imply a
    wire.t PASS for the same tag. This is the classic false-green substrate: the
    instrument's own reference input is not single-valued. Confidence: HIGH
    (mechanically confirmed).

H2. FP-TOLERANCE AXIS IS DEAD IN PRODUCTION (dualvar_policy token mismatch).
    BehaviorRecord.pm:44 default and RunUnderPerl.pm:188,389 BOTH emit
    dualvar_policy => 'numeric-first'. Comparator._return_values_equal
    (Comparator.pm:166-196) branches only on 'numeric' (applies fp_tolerance) and
    'string' (exact), with ALL other tokens — including 'numeric-first' — falling
    to the exact-string `eq` default (lines 190-193).
    Confirmed empirically: oracle "3" vs generated "3.0000000005" (abs diff 5e-10,
    well within the 1e-9 tolerance) yields MISCOMPILE under 'numeric-first' but
    PASS under 'numeric'. The fp_tolerance field (BehaviorRecord.pm:40) is wired
    nowhere reachable.
    Impact: today it fails SAFE (over-reports MISCOMPILE, never under-reports), so
    not an active false-green. But (a) the instrument does not behave as its own
    inline POLICY docs claim, and (b) the moment a float-returning idiom enters
    the corpus it will throw a spurious MISCOMPILE that looks like a real
    correctness alarm. The negative tests never caught this because the test
    fixture t::BehaviorRecord (comparator-neg.t:30) defaults dualvar_policy to
    'string' — the tests exercise a policy token the real oracle never emits.
    Confidence: HIGH (mechanically confirmed).

H3. EXERCISE-SPEC LAYER IS HAND-MAINTAINED PER-TAG (systemic under-exercise risk).
    [FALSE-GREEN SURFACE]
    _spec_for (GapMap.pm:319-414) is a literal per-tag dispatch: %SUB_SPECS,
    %CTOR_SPECS, and %PARAM_ARGS are hand-authored argument tables, one entry per
    idiom that needs non-degenerate input. This is exactly where the two
    false-greens this session lived (commits 30bd687b "close vacuous-pass false-
    green for parameterized idioms" and 933e00d5 "close second-order vacuous pass
    on M8/M9/M24"). The structural pattern that PRODUCED those false-greens is
    still in place: any future idiom needing a representative arg requires a human
    to remember to add a %PARAM_ARGS entry, and the failure mode of forgetting is
    a SILENT vacuous PASS (method runs the undef-arg path on both sides, agrees,
    PASS).
    check_spec_completeness (GapMap.pm:275-309) is a real and useful guard — it
    catches "declared param but zero args supplied" via regex param-counting
    (lines 641-680) and downgrades to UNDER_SPECIFIED. BUT it is a COUNT check
    only: it cannot detect that the supplied arg fails to exercise the
    INTERESTING branch (e.g. passing n=0 to an idiom whose interesting behavior is
    the n>0 path). It catches "no args for a parameterized method"; it does NOT
    catch "args present but semantically degenerate." The bilateral-coverage
    burden (true AND false branch) is pushed entirely onto hand-authored batch
    tests, with no structural enforcement that both were written.
    Impact: the general vacuous-pass class is PARTIALLY closed (arity gap closed,
    semantic-degeneracy gap open). The spec layer will need editing for every new
    idiom and will silently under-exercise any idiom whose author forgets the
    %PARAM_ARGS entry. This is a stringly-typed per-tag config with a silent
    failure mode — the highest-maintenance, highest-risk surface in the system.
    Confidence: HIGH.

### MEDIUM

M1. TWO ADVERTISED AXES ARE NEVER POPULATED (observability theater).
    object_state and aliasing_topology are hardcoded {} at every oracle emission
    site (RunUnderPerl.pm:185,189,387,391) and merely passed through on decode
    (302-306, 408-412). BehaviorRecord documents elaborate policies for both
    (BehaviorRecord.pm:46-49, 111-157) that no code path ever produces. The
    _is_degenerate guard (Comparator.pm:131-141) DOES inspect object_state, so an
    idiom whose only observable effect is field mutation with a void/empty return
    would be flagged as empty-record collusion (MISCOMPILE) rather than compared —
    fails safe, but for the wrong reason. No tier-1 idiom is mutation-only (I1's
    effect is observed via m()'s return), so latent.
    Impact: the record overstates its coverage; a reader trusts a 10-axis compare
    that is really a 5-axis compare. Becomes active the moment a pure-side-effect
    idiom (e.g. a setter) enters the corpus. Confidence: HIGH that the axes are
    empty; MED on impact (no current trigger).

M2. _normalize_stderr OVER-STRIPS (unanchored regex).
    Comparator.pm:204-206 and the parallel BehaviorRecord.pm:88-91 apply
    `s{ at \S+ line \d+\.?\n?}{...}g` UNANCHORED and GLOBAL. It will erase any
    substring matching " at <nonspace> line <digits>" anywhere in stderr, not
    just the trailing die/warn footer. A snippet that legitimately warns text like
    "... found at /etc/passwd line 5 ..." has that span deleted on both sides.
    I confirmed the substitution fires mid-message. It only collapses to a
    false-MATCH if the surrounding text is otherwise identical, so in practice it
    is narrow — but it is a content-erasing normalization with no anchor, which is
    a latent false-green if two stderrs differ ONLY inside an "at X line N" span.
    Note: the BehaviorRecord.normalize_stderr method (line 88) and the Comparator's
    private _normalize_stderr (line 204) are DUPLICATED regex logic — the
    comparator does not call the record's policy method, so the two could drift.
    Confidence: HIGH on over-strip; MED on real-world impact.

M3. GapMap.pm IS A BORDERLINE GOD-OBJECT.
    682 lines holding: REJECT registry, DEFERRED registry, valid_verdicts,
    tier1_green (green DEFINITION), classify_verdict_from_meta, generate
    (orchestrator + artifact I/O), validate_coverage, check_spec_completeness,
    _spec_for + %PARAM_ARGS (the exercise-spec config), corpus loading, tag
    enumeration, summary building, and two regex param-counters. That is at least
    four distinct responsibilities: (a) the green/verdict POLICY, (b) the
    exercise-spec CONFIG, (c) the orchestration GENERATOR, (d) artifact I/O.
    Verdict: not yet unmaintainable, but it concentrates the policy decisions
    (what counts as green, what is rejected, how idioms are exercised) in the same
    file as the mechanical generator. The exercise-spec config (H3) is the part
    most likely to grow and most likely to need to live elsewhere. Watch this file
    as tier-2 lands. Confidence: MED (judgment call).

M4. DETERMINISM GATE (C8) IS SHALLOW + PARTLY COSMETIC.
    wire-determinism.t T1-T3 emit the SAME graph object twice IN ONE PROCESS and
    compare. That cannot catch PERL_HASH_SEED-driven nondeterminism (same process =
    same seed). A real determinism gate would re-run under a perturbed
    PERL_PERTURB_KEYS / fresh process. T4 (lines 76-90) is COSMETIC: it perturbs a
    string the TEST constructs (`$str1 . ' '`) and asserts isnt() — it tests that
    `isnt` works, not that the emitter is deterministic. T5 only asserts the
    emission_meta keys EXIST. The gate is bolt-on (a separate test file) rather
    than enforced in the rig, and it under-tests the actual determinism invariant
    the project cares about (cross-run byte-identity). Confidence: HIGH.

### LOW

L1. emission_meta.emitted_for_every_construct is COARSE (PerlDriver.pm:117-121).
    Any non-empty generate() output sets emitted_for_every_construct => 1. There
    is no per-construct accounting — a graph that emits 3 of 4 constructs but
    produces non-empty text is treated as "complete," shifting the divergence into
    a MISCOMPILE (correctness alarm) rather than a GAP. For hand graphs this is
    fine (the author wires every node), but the flag name promises more than the
    implementation delivers; when tier-2 mined graphs arrive with partial-emit
    backends this coarseness will misclassify GAPs as MISCOMPILEs. Confidence: MED.

L2. capture() and capture_sub() DUPLICATE the entire driver-program heredoc and
    the BehaviorRecord-construction tail (RunUnderPerl.pm:117-218 vs 338-397, and
    296-307 vs 402-413). The two heredocs have already diverged slightly (capture
    imports weaken/refaddr at line 122; capture_sub does not, line 343). Copy-paste
    divergence risk in the most trust-critical file. Confidence: HIGH (verbatim
    duplication present).

L3. Per-builder boilerplate in HandGraphs.pm (the 4016-line question — see below).

---

## THE HandGraphs.pm 4016-LINE QUESTION — VERDICT

Verdict: ACCEPTABLE as a god-FILE; a REAL but bounded duplication problem.

- It is NOT a god-object: 76 _build_<TAG> subs (verified count) + a flat
  %BUILDERS dispatch table (HandGraphs.pm:3937) + a 5-line graph_for (58-63).
  Cyclomatic complexity per builder is trivial; there is no shared mutable state;
  each builder is independently readable with a header comment showing the source
  idiom and intended SoN shape (e.g. A1 at lines 65-130). For hand-authored
  fixtures this flat structure is legitimate and arguably preferable to a clever
  abstraction.
- It IS heavily duplicated: every builder repeats the same five-part ritual —
  new NodeFactory; make Start; make Constant(s); set_control_in chain; build
  Graph + merge every node; new MOP + declare_class + declare_method. Compare
  _build_A1 (65-130), _build_A4 (140-182), _build_A5 (191-216), _build_E1
  (225-...): the Constant-construction and graph->merge(...) loop is near-
  identical copy-paste. A thin helper layer (e.g. a builder that takes a node
  list and wires Start->...->Return control + merges all + wraps a single-method
  MOP) would remove ~60% of the line count and, more importantly, remove the
  per-builder opportunity to mis-wire a control edge or forget a merge (a
  mis-authored graph is a real false-green vector — see hand-graphs-neg.t N4,
  which exists precisely because authors can get this wrong).
- Scaling boundary is CLEAN: per the project memory, tier-2/3 graphs come from
  mining / B::SoN, NOT hand-authoring. HandGraphs is therefore inherently bounded
  to tier-1 (~78 idioms). It will not grow to hundreds. So the file size is
  capped and the duplication, while real, is a one-time tier-1 cost.

Net: do not split the file by line count; DO factor the construction boilerplate
into a helper before authoring more builders, because the duplication is an
active mis-authoring (false-green) surface, not merely a style smell.

---

## GapMap.pm GOD-OBJECT QUESTION — VERDICT

Verdict: BORDERLINE — real concentration of concerns, not yet a crisis.
See M3. The specific extraction that would most reduce risk is pulling the
exercise-spec layer (_spec_for, %PARAM_ARGS, %SUB_SPECS, %CTOR_SPECS,
check_spec_completeness, the two param-counters) OUT of GapMap into its own
module. That layer (a) has a distinct responsibility (how to EXERCISE an idiom,
vs. how to CLASSIFY a verdict), (b) is the documented home of two prior
false-greens, and (c) is the part guaranteed to grow per-idiom. Leaving the green
DEFINITION (tier1_green, registries) in GapMap is fine — that is genuinely the
orchestrator's policy. Co-locating the exercise CONFIG with it is the smell.

---

## HOTSPOTS (top 3 files to watch)

1. lib/Chalk/CodeGen/Harness/GapMap.pm — holds the green definition AND the
   per-tag exercise-spec config (H3, M3). This is where false-greens are born
   (two already were). Highest behavioral risk per edit.
2. lib/Chalk/CodeGen/Harness/RunUnderPerl.pm — the trust root. Two duplicated
   driver heredocs already diverging (L2); the dualvar_policy token it emits is
   the one the comparator ignores (H2). Every edit here can silently change what
   "truth" means.
3. lib/Chalk/CodeGen/Harness/HandGraphs.pm — bounded but duplication-heavy;
   each new builder is a fresh chance to mis-wire control/merge (mis-authored-
   graph false-green, guarded only by eyeball cross-checks like
   hand-graphs-neg.t N4).

Honorable mention: Harness.pm %CORPUS (H1) — the forked second source of truth.

---

## QUESTIONS FOR PHASE 2 (does the architecture hold as tier-2 mining + the C corner arrive?)

Q1. SINGLE SOURCE OF TRUTH: tier-2 mines graphs and snippets from real source /
    B::SoN. With H1 already showing the tier-1 corpus forked between a hardcoded
    table and a file, what is the ONE authoritative corpus representation for
    tier-2, and does run_entry get retired in favor of the file-driven GapMap path
    (or vice versa)? Two readers of "truth" will not survive hundreds of mined
    idioms.

Q2. emitted_for_every_construct (L1) is coarse-grained and currently safe only
    because hand graphs are complete by construction. Mined/partial-emit graphs
    will need per-construct emission accounting, or every partial emit becomes a
    spurious MISCOMPILE. Is there a plan to make emission_meta granular before
    tier-2?

Q3. The exercise-spec layer (H3) is hand-authored per tag. Tier-2's volume makes
    hand-authoring %PARAM_ARGS infeasible. Where do representative/bilateral
    arguments come from for mined idioms — inferred from the source call sites,
    or generated? Without an answer, tier-2 either under-exercises silently or
    stalls on manual spec authoring.

Q4. THE C CORNER: when a C/XS backend is added, the P-side driver
    (PerlDriver -> Target::Perl) gains a sibling (Target::C -> compile -> run).
    Does the BehaviorRecord/Comparator contract survive a backend whose
    observable axes differ (e.g. C-level integer overflow, NV formatting, dualvar
    semantics)? The currently-dead FP-tolerance and dualvar policies (H2) become
    LOAD-BEARING the moment a C backend produces a numerically-equal-but-string-
    different result. H2 must be fixed BEFORE the C corner, or the harness will
    flag every C numeric idiom as MISCOMPILE.

Q5. object_state / aliasing_topology (M1): tier-2 will certainly include
    mutation-only and shared-reference idioms. The two empty axes must be
    populated before then, or the harness silently cannot see the very behaviors
    a C backend is most likely to get wrong (aliasing, refcount, weakref).
