# Target::* `feature class` conversion — blockers audit

**Date:** 2026-08-24
**Scope:** `lib/Chalk/Target/LLVM.pm`, `lib/Chalk/Target/LLVM/Context.pm`, `lib/Chalk/Target/LLVM/ElaboratedContext.pm`
**Mode:** read-only. No file under `lib/` or `t/` was modified.

## Measurement baseline (IMPORTANT)

A second agent is actively editing these files. `@NEED_FLAGS` has already
MOVED from `LLVM.pm` into `Context.pm` in the working tree
(working tree: `Context.pm:154`; HEAD: `LLVM.pm:648`), and two new methods
`absorb_need_flags_from` / `inherit_need_flags_from` exist in the working
tree only (`Context.pm:170`, `:181`).

**Every count in this document is measured against `git show HEAD:` copies**,
extracted to `scratchpad/head/`, so the numbers are stable and reproducible.
HEAD matches the brief exactly:

```
7528 scratchpad/head/Context.pm   139 subs   41 $self slots
1653 scratchpad/head/LLVM.pm       18 subs    0 $self
  73 reach-ins from LLVM.pm into a ctx hash
```

Where I quote a working-tree line number I say so explicitly.

## Oracles used

- **External oracle (primary):** the Perl 5.42.0 `feature class` implementation
  itself, at `$HOME/.local/share/pvm/versions/5.42.0/bin/perl`. Every claim
  about what `feature class` does or does not permit is backed by a probe
  script run against that interpreter, with output quoted inline.
- **External oracle (secondary):** the existing test suite as a *regression
  guard only* — used to establish which tests are red BEFORE any conversion,
  not to establish correctness.
- **Compat-trail oracle:** `ElaboratedContext.pm`'s own header comment names
  itself a surviving alias; `Chalk::IR::Target`'s die-stub is a marker of a
  contract that no longer executes.
- **No oracle exists** for "should `Chalk::Target::LLVM` be a class at all."
  The owner has ruled that it must be. Finding 5 reports the measured cost of
  that ruling and does not relitigate it.

---

## Summary — the single hardest blocker

**`Chalk::Target::LLVM->lower(...)` is a class method call on a package that
will have no instance, and `feature class` makes that a hard runtime error.**
Under `feature class`, a `method` may only be invoked on an instance: invoking
one on the bare class name dies with `Cannot invoke method "lower" on a
non-instance`. `lower` and `lower_with_elaboration` are called as class methods
from **205 call sites across 66 files** (`lib/` and `t/`), and `LLVM.pm` has no
state to construct an instance *from* — it has zero `$self` and 16 of its 18
subs are pure functions that never see an invocant. So the conversion forces a
choice at 205 sites: either every caller is rewritten to construct-then-call
(`Chalk::Target::LLVM->new->lower(...)`), or `lower`/`lower_with_elaboration`
are declared as `sub` rather than `method` inside the `class` block — which
keeps all 205 callers working untouched but means the two entry points that
define the target contract are the only two things in the class that are *not*
methods. This is not a mechanical rewrite; it is a contract decision about
whether a Target is a value or a namespace, and it must be made before the
first line is converted. Note also that `Chalk::IR::Target` — LLVM.pm's parent,
already a `feature class` — has exactly this defect *today*: its `method lower`
die-stub is unreachable, and the test asserting it (`target-hierarchy.t:65-70`)
passes vacuously via `->can`. The bug the conversion would introduce is already
in the repo, one level up, undetected.

**Counts:** 3 hard blockers, 4 structural complications, 2 pre-existing latent
defects surfaced, 1 premise in the brief corrected.

---

## Finding 1: the glob shim — the brief's premise is incorrect

**Question asked:** "`feature class` does not support symbol-table aliasing into
a class body."

**This is false.** Measured directly:

```
$ perl /tmp/probe2.pl
1. glob-alias inside class body: COMPILED
   call: shared(x)
```

Probe source (a `class` body containing `*GlobIn::shared = \&Helper::shared;`
plus a `method m { return shared("x") }`) compiled and executed correctly. A
`class` block is still a package; the symbol table is still there; a glob
assignment inside it still installs a sub, and unqualified calls still resolve
to it. **The glob shim is not a blocker.** It can be carried across the
conversion unchanged.

**Site count.** `Context.pm:37` (HEAD):

```perl
*_require_repr              = \&Chalk::Target::LLVM::_require_repr;
```

- **27 bare `_require_repr(...)` call sites** in `Context.pm` depend on it:
  lines 1710, 1778, 1836, 1854, 1885, 2365, 2373, 2374, 2740, 2841, 4121,
  4297, 4343, 4893, 5002, 5030, 5285, 5656, 5696, 6187, 6982, 7016, 7065,
  7118, 7165, 7267, 7455.
- **1 fully-qualified site**: `Context.pm:37` itself (the alias).
- Definition: `LLVM.pm:80`. Other callers: `LLVM.pm:527`, `LLVM.pm:539`.

**Minimal correct fix.** Since the shim is *not* forced by `feature class`, the
laziest correct answer is **change nothing** — carry line 37 forward verbatim.
If it is to be removed anyway (it is a genuine compat trail), the smallest
correct move is **move the sub into `Context.pm` and have `LLVM.pm` call it
qualified at its 2 sites**, rather than qualify 27 sites in `Context.pm`. Do
not make it a `method`: it takes `($node, $where)` and has no invocant, so
making it a method would require editing all 29 call sites to add `$self->`
for no gain.

**Other symbol-table manipulation in the three files:** exactly one glob
assignment, the one above. Grep for `\*NAME = \&`, `no strict 'refs'`,
`AUTOLOAD`, `DESTROY`, `@ISA` across all three files returns no other hits.
There is **one glob assignment from outside**, which is a separate blocker —
see Finding 3.

**Layer responsible:** none. Non-issue.

---

## Finding 2: `local $self->{...}` — a genuine hard blocker

**Trigger / minimal failing case:**

```
$ perl /tmp/probe5.pl
local on class field hash elem: COMPILED
  call: 1
local on class scalar field: FAILED: Can't localize lexical variable $s
```

`feature class` fields are **lexicals**, and `local` does not work on lexicals.
`local $h{x}` on a `field %h` works (localizing a hash *element* of an
aggregate field is fine); `local $s` on a `field $s` is a compile-time failure,
and so is `local $cache` on a `field $cache = {}`:

```
local on hashref-valued field: FAILED: Can't localize lexical variable $cache
```

**Site count and locations (HEAD `Context.pm`):**

| Line | Statement | Field |
|------|-----------|-------|
| 5781 | `local $self->{_inlining} = { ($self->{_inlining} // {})->%*, $name => 1 };` | `_inlining` |
| 5871 | `local $self->{_arg_bind} = { ($self->{_arg_bind} // {})->%* };` | `_arg_bind` |
| 6007 | `local $self->{_mut_read_memo} = {};` | `_mut_read_memo` |
| 6010 | `local $self->{cache} = {};` | `cache` |

All four localize a **whole slot**, not an element, so none is the working
`local $h{x}` shape. All four are in the direct-call inliner
(`_lower_call_direct` at 5759, `_lower_inlined_effects_then_value` at 6004).

**Why this is load-bearing, not incidental.** The `cache` and `_mut_read_memo`
localizations at 6007/6010 are the inliner's *correctness* isolation. The
comment immediately above them (HEAD `Context.pm:6000-6003`) states the hazard
explicitly: a callee's pure subexpression memoized during the effect-chain
drive must not leak into the value lowering. This is the cross-graph id-keyed
cache collision family. A conversion that silently drops or mistranslates these
four `local`s reintroduces a **known miscompile class**, and the corpus would
not necessarily catch it.

**Evidence:** probe output above; `grep -n "local \$self->{" scratchpad/head/Context.pm`
returns exactly these 4 lines.

**Layer responsible:** IR lowering (the direct-call inliner).

**Suggested remediation shape:** manual save/restore around the dynamic extent,
which is measured to work:

```
$ perl /tmp/probe6.pl
manual save/restore of %field: COMPILED
  inner=0 outer=2
```

i.e. copy the field out, clear it, run the body, copy it back. **Side effects
of the fix:** `local` is exception-safe and manual restore is not — if the body
`die`s (and these very functions `die "GAP: ..."` at `Context.pm:5777` on
recursion detection, inside the localized extent at 5781), a manual restore is
skipped and the field stays clobbered. Any hand-rolled replacement must restore
on the die path too, or the GAP-die at 5777 will corrupt the inliner state of
whatever catches it. This is the subtlest correctness risk in the whole
conversion.

---

## Finding 3: class-method invocation — the primary blocker

**Trigger / minimal failing case:**

```
$ perl /tmp/probe4.pl
A. T->lower($ret) [current call pattern]: DIED: Cannot invoke method "lower" on a non-instance
B. sub-in-class, T2->lower(42): lowered:42
C. T->can(lower):  TRUE
D. T2->can(lower): TRUE
E. Kid->lower(1) [inherited method, no instance]: DIED: Cannot invoke method "lower" on a non-instance
F. Kid->isa(Base): TRUE
```

A `method` inside a `class` cannot be invoked on the class name. A plain `sub`
inside a `class` body can (probe B). Note C and D: **`->can()` returns TRUE in
both cases**, so `can`-based tests cannot distinguish a working entry point
from a broken one.

**Site count and locations:** 205 call sites of `Chalk::Target::LLVM->lower` /
`->lower_with_elaboration` across 66 distinct files in `lib/` and `t/`.
Representative: `t/lib/Chalk/CodeGen/Harness/LLVMDriver.pm:67`,
`t/lib/Chalk/CodeGen/Harness/ProgramRunner.pm:207`,
`t/lib/Chalk/CodeGen/Harness/Mode2Adapter.pm:166`,
`t/lib/Chalk/CodeGen/Harness/Phase5LibCoverage.pm:111`,
`t/bootstrap/corpus/son-corpus-wide.t:88`, `t/bootstrap/corpus/son-e2e.t:100`,
`t/bootstrap/ir/llvm-lowering.t:42`. The four `t/lib/` harness modules are on
the corpus gate path, so a mistake here breaks the gate, not just a unit test.

**Sub-finding 3a — the same defect already exists in `Chalk::IR::Target`.**
`LLVM.pm:11` is `use parent 'Chalk::IR::Target'`, and `lib/Chalk/IR/Target.pm`
is already a `feature class` with `method lower($graph_or_node)`. Measured:

```
$ perl -Ilib -e 'use Chalk::IR::Target; eval { Chalk::IR::Target->lower("x") }; print $@'
Cannot invoke method "lower" on a non-instance
```

The stub's advertised behaviour — `die ref($self) . " must implement lower()"`,
`Target.pm:26` — is **unreachable**. It cannot fire for its stated purpose.
Its guarding test, `t/bootstrap/codegen-harness/target-hierarchy.t:65-70`,
asserts only `Chalk::IR::Target->can('lower')`, which is TRUE for an
uninvokable method (probe C). Test 6 at `target-hierarchy.t:72-84` carries the
comment *"Verify it is a real method (not just inherited stub that dies
immediately)"* and then checks only `ref($ref) eq 'CODE'` — also vacuously
true. Both tests pass today and would keep passing through a broken conversion.

**Sub-finding 3b — a test monkeypatches the entry point via glob.**
`t/bootstrap/codegen-harness/g1-miscompile-classification.t:159`:

```perl
local *Chalk::Target::LLVM::lower_with_elaboration = sub { ... };
```

I probed this specifically, expecting it to be a blocker. **It is not:**

```
$ perl /tmp/probe_class.pl
glob-assign to class method: SUCCEEDED-compiletime
  after patch, call gives: patched
```

Overriding a `feature class` method by glob assignment works. Recorded here
because it looks like a blocker and is not — but note the override installs a
plain `sub`, which under Finding 3's semantics is then *class-method callable*
where the original `method` would not be. If `lower_with_elaboration` becomes a
`method`, this test would paper over the non-instance failure rather than
exposing it.

**Layer responsible:** target/codegen entry contract.

**Suggested remediation shape:** the two entries stay `sub`, not `method`,
inside the `class` block (probe B), leaving all 205 callers untouched. **Side
effects:** the class then has two entry points that are not methods, and
`Chalk::IR::Target`'s `method lower` stub must become a `sub` too or the
inheritance contract remains decorative. Fixing `Chalk::IR::Target` is a
prerequisite, not a follow-up — and it will need a non-vacuous test, since the
two existing ones cannot detect the difference.

---

## Finding 4: `sub new` and construction

**What `Context::new` does beyond populating the hash** (HEAD `Context.pm:51-145`):

1. `delete $args{elab}` and `delete $args{class_registry}` from `%args`
   (`:74-75`). `%args` is then **discarded** — any other key passed is silently
   ignored. This is the exact trapdoor the `ElaboratedContext.pm:22-26` comment
   says was closed; a narrower version of it survives.
2. Constructs the entry block hashref `$entry_block` (`:79`).
3. Calls `_index_elab_phis($elab)` (`:143`) — a real computation that walks
   `$elab->emitted_phis` and builds a by-block index (`:150-158`).

Item 3 is the only work that must move to `ADJUST`. Items 1-2 are field
defaults expressible directly (`field $entry_block`... though see below).

**A silent behaviour change to name.** `feature class`'s generated constructor
is **strict about unrecognised parameters**:

```
$ perl /tmp/probe3.pl
   F->new(zz=>1) : DIED: Unrecognised parameters for "F" constructor: zz
```

Today `Context->new(anything => 1)` succeeds and ignores it. After conversion
it dies. That is an improvement, but it is a behaviour change at every
construction site, and it will surface any caller currently passing a
misspelled or obsolete key. Construction sites are few (see below), so this is
low-risk but must be checked rather than assumed.

**Construction routes other than `->new`:** exactly one `bless` in the three
files, `Context.pm:80`, inside `new` itself. No hash-literal-then-bless, no
cloning, no `Storable::dclone`. **Variable-class-name construction: none** in
the three files. (Probed for completeness: `my $cn = "F"; $cn->new` works fine
under `feature class` — probe3 line 4 — so it would not be a blocker anyway.)

**All construction sites (5 total):**

| Site | Call |
|------|------|
| `LLVM.pm:851` | `ElaboratedContext->new(...)` |
| `LLVM.pm:976` | `ElaboratedContext->new(...)` |
| `LLVM.pm:1024` | `Chalk::Target::LLVM::Context->new` — **no arguments** |
| `LLVM.pm:1158` | `ElaboratedContext->new(elab => $elab, class_registry => ...)` |
| `t/bootstrap/ir/llvm-call-direct-effect-guard.t:23`, `llvm-module-global-name.t:10`, `llvm-mainline-die.t:71` | `Context->new` — no arguments |

The no-argument form must keep working: `field $elab :param = undef;` gives
that for free (probe3 test 2: `F->new()` succeeds with the default).

---

## Finding 5: inheritance and method resolution

**`ElaboratedContext` is a pure alias.** `lib/Chalk/Target/LLVM/ElaboratedContext.pm`
is 51 lines of which 47 are comment. Its entire executable content is:

```perl
package Chalk::Target::LLVM::ElaboratedContext;
use 5.42.0;
use utf8;
use parent 'Chalk::Target::LLVM::Context';
1;
```

It defines **zero subs**, **zero fields**, and **zero overrides**. It adds
nothing. It is a name, and its own header comment (lines 1-32) says so.

**`:isa()` requires a real class — confirmed:**

```
$ perl -I/tmp/pl/lib /tmp/pl/t.pl
1. :isa(PLAIN PACKAGE): FAILED: Class :isa attribute requires a class but "PlainParent" is not one
```

(My first attempt at this probe failed on `Can't locate PlainParent.pm` — a
module-loading error, not a semantic one. Re-run against a real file on disk,
the above is the true result.) So the brief is right: **they convert together
or not at all.** `class :isa(class)` works and inherits the constructor
(probe3 test 5: `Sub2->new(a=>3)->a` returns 3).

Because ElaboratedContext overrides nothing, the alternative — delete the file
and rename its 4 call sites — is strictly less work than converting it. That is
an observation about cost, not a recommendation; the 4 sites are `LLVM.pm:851`,
`:976`, `:1158`, and the name appears in `t/` only via `Context` (grep for
`LLVM::ElaboratedContext` in `t/` returns no hits).

**`SUPER::` calls:** **none** in any of the three files. The only occurrences of
the string `SUPER::` are in comments at `ElaboratedContext.pm:23` and
`Context.pm:71`, both describing the *deleted* subclass constructor.

**`AUTOLOAD` / `DESTROY`:** **none** in any of the three files.

**`can()` / `isa()` introspection on these classes:** the ~80 `->can(...)` hits
in `Context.pm` and `LLVM.pm` are **all on IR nodes** (`->can('operation')`,
`->can('control_in')`, `->can('dispatch_kind')`, `->can('representation')`,
etc.), not on Context or LLVM. Introspection on the classes themselves occurs
only in `t/bootstrap/codegen-harness/target-hierarchy.t` (lines 33, 74, 79) and
`t/bootstrap/ir/llvm-lowering.t:23`. See Finding 3a: these are the vacuous ones.

**Name collisions between the 139 Context subs and the 18 LLVM subs:**
exactly one — **`_method_fn_type`**, defined at `LLVM.pm:203` and again at
`Context.pm:41`. This is a *deliberate, documented duplicate*; `Context.pm:39-40`
says so: *"Duplicate of the module-level sub; both packages need it to avoid
cross-package calls."* Since the two packages are not in an inheritance
relationship with each other, this changes no resolution today and will change
none after conversion. It is, however, a copy-paste divergence hazard: the two
bodies must agree and nothing enforces it. **Not a blocker; a latent defect.**

**Cross-package calls (the coupling that *does* matter):**
- `Context.pm` → `LLVM.pm`: 2 sites — `Context.pm:37` (the glob alias) and
  `Context.pm:6257` (`Chalk::Target::LLVM::_method_fn_llvm_ret_type`).
- `LLVM.pm` → `Context.pm`: 4 sites — `LLVM.pm:716`, `:1408`
  (`Context::_str_type_decl()`), `LLVM.pm:722`, `:1509`
  (`Context::_strpair_type_decl()`). All four call `Context` subs as **plain
  functions**, fully qualified. Under `feature class` a `sub` in a class body
  is still callable this way (probe2 test 3: `SC::s_cm()` returns `s_cm()`), so
  these survive — **provided** `_str_type_decl` and `_strpair_type_decl` stay
  `sub`, not `method`.

---

## Finding 6: non-method subs in `Context.pm`

Of the 139 subs, **29 never mention `$self`**. Of those, 2 are false positives
(`blocks` and `instructions` are methods written as `$_[0]->{...}`) and `new`
is the constructor. So:

- **112 true methods** (take `$self`, become `method`)
- **2 methods written positionally** — `blocks` (`:448`), `instructions`
  (`:452`), both `$_[0]->{...}`; become `method`
- **1 constructor** — `new` (`:51`); becomes the generated constructor + `ADJUST`
- **24 genuine non-method subs** — stay `sub`

### The 24 non-method subs (definitive list, HEAD line numbers)

| Line | Sub | First arg | Note |
|------|-----|-----------|------|
| 41 | `_method_fn_type` | `$result_repr` | duplicate of `LLVM.pm:203` |
| 150 | `_index_elab_phis` | `$elab` | called from `new`; moves to `ADJUST` |
| 229 | `_str_idx` | `$_[0]` | reads `my %_STR_IDX` |
| 231 | `_str_fields` | — | reads `my @_STR_FIELDS`; **called from `t/`** |
| 233 | `_str_type_decl` | — | **called from `LLVM.pm:716,:1408`** |
| 237 | `_str_size_bytes` | — | **called from `t/`** |
| 240 | `_strpair_fields` | — | **called from `t/`** |
| 243 | `_strpair_type_decl` | — | **called from `LLVM.pm:722,:1509`** |
| 250 | `_strpair_size_bytes` | — | **called from `t/`** |
| 256 | `_struct_size_bytes` | `@fields` | slurpy |
| 653 | `_mutable_read_ops` | — | test-only accessor; **called from `t/`** |
| 654 | `_pure_descend_ops` | — | test-only accessor; **called from `t/`** |
| 3091 | `_repr_to_llvm_type` | `$repr` | **has a signature** — see below |
| 3721 | `_phi_slot_from_predecessors` | `$phi` | |
| 3738 | `_phi_slot_for_proj` | `$region` | |
| 3775 | `_proj_index_of_control` | `$node` | |
| 4058 | `_find_unwind_consumer` | `$node` | |
| 4467 | `_phi_has_live_consumer` | `$phi` | |
| 4473 | `_collect_loop_phis` | `$loop_node` | |
| 4493 | `_is_memory_phi` | `$phi` | |
| 4615 | `_find_proj_consumer` | `$node` | |
| 4629 | `_collect_branch_body` | `$proj_node` | |
| 4637 | `_collect_body_recursive` | `$node` | |
| 6027 | `_is_args_array` | `$node` | |
| 6337 | `_regex_escape_byte` | `$chars` | |
| 7205 | `_parse_subst_replacement` | `$repl` | |
| 7506 | `_infer_class_name_from_obj` | `$obj_node` | |

(27 rows; `_method_fn_type`, `_index_elab_phis` and `_repr_to_llvm_type` are
called out separately above, giving 24 that are purely "stay a `sub`".)

**`_repr_to_llvm_type` is the one sub in either file using a signature**, and
it uses a `//= die` default (`Context.pm:3091`):

```perl
sub _repr_to_llvm_type ($repr //= die "node reached machine-type selection with NO representation (undef) — ...") {
```

That die-on-missing-argument is *tested behaviour*:
`t/bootstrap/ir/llvm-repr-to-llvm-type-undef-guard.t:19` (explicit `undef`) and
`:32` (no argument at all). It must stay a `sub` — converting it to `method`
would shift the argument position by one and both tests call it as a plain
qualified function (`Context::_repr_to_llvm_type(...)`).

**Nine of these 24 are called from `t/` as plain functions** (marked above),
which pins them as `sub` regardless of preference — see Finding 8.

---

## Finding 7: `LLVM.pm`'s shape

**Never instantiated; zero `$self`.** Confirmed: `grep -c '\$self' scratchpad/head/LLVM.pm`
returns 0, and there is no `bless` and no `new`.

### The 18 subs, classified

| Line | Sub | Signature | Invocation |
|------|-----|-----------|------------|
| 53 | `lower` | `($class, $return_node, %opts)` | **class method**, 205 external sites |
| 1140 | `lower_with_elaboration` | `($class, $return_node, $elab, %opts)` | **class method**, external + `lower` |
| 80 | `_require_repr` | `($node, $where)` | plain fn (+ glob-aliased into Context) |
| 89 | `_encode_c_string` | `($str)` | plain fn |
| 125 | `_emit_str_to_num_helper` | *(no `@_` unpack)* | plain fn |
| 203 | `_method_fn_type` | `($result_repr)` | plain fn (duplicated in Context) |
| 217 | `_method_fn_llvm_ret_type` | `($repr)` | plain fn; **called from `Context.pm:6257`** |
| 248 | `_flatten_inheritance` | `($registry)` | plain fn |
| 326 | `_build_registry_from_mop` | `($mop)` | plain fn |
| 366 | `_method_body_root` | `($mop_method)` | plain fn |
| 405 | `_method_body_return` | `($mop_method)` | plain fn |
| 428 | `_phaser_body_in_control_order` | `($phaser)` | plain fn; **called from `t/bootstrap/ir/llvm-mop-direct.t:261`** |
| 476 | `_populate_registry_from_mop_class` | `($registry, $cls)` | plain fn; **called from `t/bootstrap/corpus/harness-strictness.t:90,:106`** |
| 622 | `_render_context_blocks` | `($ctx, $skip_first_label)` | plain fn |
| 661 | `_propagate_need_flags` | `($dst_ctx, $src_ctx)` | plain fn *(moved to Context in working tree)* |
| 673 | `_render_str_globals` | `($body_ctx)` | plain fn |
| 692 | `_emit_class_registry_ir` | `($registry, $ctx)` | plain fn |
| 1080 | `_process_control_chain` | `($ctx, $return_node)` | plain fn |

**16 of 18 are plain functions.** Only `lower` and `lower_with_elaboration`
take an invocant, and in both cases `$class` is used **solely to redispatch**:

```perl
sub lower {
    my ($class, $return_node, %opts) = @_;
    my $dom  = Chalk::IR::Schedule::Dominators->from_return_node($return_node);
    my $elab = Chalk::IR::Schedule::Elaborate->from_return_node($return_node, $dom);
    return $class->lower_with_elaboration($return_node, $elab, %opts);
}
```
(`LLVM.pm:53-58`.) In `lower_with_elaboration`, the 6 occurrences of the string
`$class` in the body are all the *unrelated* local `my $class_registry` — the
invocant `$class` itself is never used after unpacking.

### What would its fields be?

**Zero.** There is no state. The three module-level `my` variables are constant
tables, not instance state:
- `my @NEED_FLAGS` (`LLVM.pm:648` at HEAD; already relocated in the working tree)
- the `%_REPR_*` tables live in `Context.pm`, not here

All per-lowering state lives on the `Context` object, which is why `LLVM.pm`
has 73 reach-ins into it. A `class Chalk::Target::LLVM { }` would have an empty
field list.

**Honest assessment, with evidence both ways.** The evidence that a class is
the wrong shape: zero fields, zero `$self`, 16/18 pure functions, and the only
two invocant-taking subs use the invocant for nothing but redispatch — which is
the textbook definition of a namespace, not an object. The evidence that a
class is the right shape: `Chalk::IR::Target` already *is* a class and declares
`lower` as the contract, so LLVM.pm is currently a plain package pretending to
implement a class's interface — the mismatch already exists and `use parent`
merely hides it; and the 73 reach-ins into `Context`'s hash are precisely the
state that *should* be somewhere, so "zero fields" may be a symptom of state
having leaked into the wrong object rather than proof that no state exists.
That second reading is strengthened by Finding 8: 9 of the slots `LLVM.pm`
manipulates on `Context` are slots `Context` itself never mentions.

The owner has ruled; this section is the cost, not an argument.

---

## Finding 8: the field list

`$self->{...}` in `Context.pm` yields **41 distinct slots** (matching the
brief). But `LLVM.pm` writes and reads **9 further slots on the same hash that
`Context.pm` never mentions at all**. The true field count for the class is
therefore **50**, and 9 of them are invisible from inside the file that would
own them.

### The 9 slots that exist only because `LLVM.pm` invents them

`_bool_str_globals_emitted`, `_getenv_emitted`, `_memcmp_emitted`,
`_need_bool_str_globals`, `_need_print_int_fmt`, `_str_to_num_helper_emitted`,
`_str_type_emitted`, `_strlen_declared`, `_strpair_emitted`.

Verified: `grep -c` for each against `scratchpad/head/Context.pm` returns 0 for
seven of them. The remaining two — `_need_bool_str_globals` and
`_need_print_int_fmt` — appear in `Context.pm` **only inside the working-tree
`@NEED_FLAGS` list** the other agent just moved there (working tree
`Context.pm:157`, `:163`); at HEAD, `Context.pm` does not mention them at all.

These 9 are pure emit-once/needs-declaration bookkeeping owned by `LLVM.pm`'s
prologue rendering. They are the clearest evidence that the reach-in removal is
not merely a style cleanup: **9 fields have to be invented on the class before
`LLVM.pm` can stop reaching in**, or moved to a separate prologue-state object.

### Slot table

`ctxW`/`ctxR` = write/read sites in `Context.pm`; `extW`/`extR` = same from
`LLVM.pm`. `new()` column: default as set at `Context.pm:80-144`, or `—` for
autovivified. Mutation: `RO` = never assigned after construction anywhere.

| Slot | new() default | ctxW | ctxR | extW | extR | External | Mutation |
|------|---------------|-----:|-----:|-----:|-----:|----------|----------|
| `blocks` | `[$entry_block]` | 0 | 10 | 0 | 0 | — | RO ref, contents mutated |
| `current_idx` | `0` | 5 | 4 | 0 | 1 | **YES** (r) | mutated |
| `counter` | `0` | 0 | 2 | 0 | 0 | — | mutated via `++` |
| `block_counter` | `0` | 0 | 2 | 0 | 0 | — | mutated via `++` |
| `cache` | `{}` | 75 | 15 | 0 | 0 | — | mutated; **`local`d at 6010** |
| `var_table` | `{}` | 5 | 12 | 0 | 0 | — | mutated |
| `class_registry` | `$class_registry // {}` | 0 | 2 | 1 | 0 | **YES (w)** | assigned at `LLVM.pm:1029` |
| `elab` | `$elab` | 0 | 0 | 0 | 0 | — | **never read** (see below) |
| `elab_phi_by_block` | `_index_elab_phis($elab)` | 0 | 1 | 0 | 0 | — | RO |
| `_str_globals` | `[]` | 0 | 2 | 0 | 5 | **YES** (r) | contents mutated |
| `_pkg_globals` | `{}` | 1 | 0 | 0 | 4 | **YES** (r) | mutated |
| `_pkg_str_globals` | `{}` | 1 | 0 | 0 | 4 | **YES** (r) | mutated |
| `_pkg_num_globals` | `{}` | 1 | 0 | 0 | 4 | **YES** (r) | mutated |
| `_need_malloc_memcpy` | `0` | 10 | 0 | 1 | 1 | **YES (w)** | mutated |
| `_need_str_to_num_helper` | `0` | 2 | 0 | 0 | 2 | **YES** (r) | mutated |
| `_need_aggregate_types` | `0` | 13 | 0 | 1 | 1 | **YES (w)** | mutated |
| `_need_memcmp` | `0` | 4 | 0 | 0 | 2 | **YES** (r) | mutated |
| `_slot_payload` | `{}` | 2 | 2 | 0 | 1 | **YES** (r) | mutated |
| `_need_strpair` | `0` | 6 | 0 | 4 | 4 | **YES (w)** | mutated |
| `_in_method_body` | `0` | 0 | 3 | 2 | 0 | **YES (w)** | set only by `LLVM.pm` |
| `_method_self_name` | `undef` | 0 | 3 | 2 | 0 | **YES (w)** | set only by `LLVM.pm` |
| `_method_class_name` | `undef` | 0 | 3 | 3 | 0 | **YES (w)** | set only by `LLVM.pm` |
| `_arg_bind` | — | 2 | 3 | 0 | 0 | — | **`local`d at 5871** |
| `_branch_guarded_store` | — | 1 | 1 | 0 | 0 | — | mutated |
| `_env_empty_global` | — | 1 | 0 | 0 | 0 | — | `//=` memo at 7132 |
| `_inlining` | — | 1 | 3 | 0 | 0 | — | **`local`d at 5781** |
| `_loop_ctx_stack` | — | 1 | 3 | 0 | 0 | — | push/pop stack |
| `_method_name` | — | 0 | 2 | 3 | 0 | **YES (w)** | set only by `LLVM.pm` |
| `_mut_read_memo` | — | 3 | 3 | 0 | 0 | — | **`local`d at 6007** |
| `_need_exit` | — | 2 | 0 | 0 | 1 | **YES** (r) | mutated |
| `_need_getenv` | — | 1 | 0 | 0 | 2 | **YES** (r) | mutated |
| `_need_num_fmt` | — | 1 | 0 | 0 | 1 | **YES** (r) | mutated |
| `_need_print_str_fmt` | — | 1 | 0 | 0 | 1 | **YES** (r) | mutated |
| `_need_snprintf` | — | 1 | 0 | 0 | 1 | **YES** (r) | mutated |
| `_need_str_type` | — | 1 | 0 | 3 | 4 | **YES (w)** | mutated |
| `_phi_forcing` | — | 0 | 3 | 0 | 0 | — | `++`/`delete` on nested hash |
| `_phi_to_vd` | — | 2 | 2 | 0 | 0 | — | mutated |
| `_regex_captures` | — | 2 | 1 | 0 | 0 | — | mutated |
| `_undef_defined_bit` | — | 3 | 4 | 0 | 0 | — | mutated |
| `_undef_payload` | — | 3 | 5 | 0 | 0 | — | mutated |
| `_unwind_emitted` | — | 0 | 1 | 0 | 0 | — | `++` on nested hash |
| `_vd_repr` | — | 1 | 1 | 0 | 0 | — | mutated |
| `_bool_str_globals_emitted` | — | 0 | 0 | 2 | 2 | **YES (w)** | **LLVM.pm-only** |
| `_getenv_emitted` | — | 0 | 0 | 2 | 1 | **YES (w)** | **LLVM.pm-only** |
| `_memcmp_emitted` | — | 0 | 0 | 2 | 1 | **YES (w)** | **LLVM.pm-only** |
| `_need_bool_str_globals` | — | 0 | 0 | 0 | 2 | **YES** (r) | **LLVM.pm-only** |
| `_need_print_int_fmt` | — | 0 | 0 | 0 | 1 | **YES** (r) | **LLVM.pm-only** |
| `_str_to_num_helper_emitted` | — | 0 | 0 | 2 | 1 | **YES (w)** | **LLVM.pm-only** |
| `_str_type_emitted` | — | 0 | 0 | 2 | 2 | **YES (w)** | **LLVM.pm-only** |
| `_strlen_declared` | — | 0 | 0 | 3 | 2 | **YES (w)** | **LLVM.pm-only** |
| `_strpair_emitted` | — | 0 | 0 | 2 | 1 | **YES (w)** | **LLVM.pm-only** |

**Totals:** 50 slots. 22 initialized in `new()`; **28 autovivified and never
declared anywhere** (20 of the 41 Context slots + the 8 LLVM-only ones beyond
the two now listed in the working-tree `@NEED_FLAGS`). 31 slots have external
touches; **17 of those are externally WRITTEN**, which is what the other agent
is removing.

**`elab` is dead.** It is set in `new` at `Context.pm:142` and **never read via
`$self->{elab}` anywhere in `Context.pm`**. Its only consumer is
`_index_elab_phis($elab)` at `:143`, which reads the local `$elab` variable, not
the slot. Verified by full-file scan: `elab` appears in the initialized set and
the used set is empty for it. Under `feature class` it would become a field
with no reader. **Not a blocker; a deletion candidate the conversion will
surface.**

---

## Finding 9: test exposure

### Tests that construct a Context or ElaboratedContext

| File:line | Call |
|-----------|------|
| `t/bootstrap/ir/llvm-call-direct-effect-guard.t:23` | `Chalk::Target::LLVM::Context->new` |
| `t/bootstrap/ir/llvm-module-global-name.t:10` | `Chalk::Target::LLVM::Context->new` |
| `t/bootstrap/ir/llvm-mainline-die.t:71` | `Chalk::Target::LLVM::Context->new` |

No test constructs an `ElaboratedContext` (grep for `LLVM::ElaboratedContext`
in `t/` returns no hits).

### Tests that depend on the Context being a hashref

**This is the sharpest test blocker.** `feature class` instances are **not**
hashrefs — measured:

```
$ perl /tmp/probe3.pl
3. ref(instance)  : F
   is it a HASH?  : NO
   $o->{x} access : DIED: Not a HASH reference
```

Sites that will die:

| File:line | Expression | Kind |
|-----------|------------|------|
| `t/bootstrap/ir/llvm-module-global-name.t:26` | `my $g = $ctx->{_str_globals}[0];` | read |
| `t/bootstrap/ir/llvm-module-global-name.t:42` | `$ctx->{_in_method_body} = 1;` | **write** |
| `t/bootstrap/ir/llvm-module-global-name.t:43` | `$ctx->{_method_class_name} = 'Point';` | **write** |
| `t/bootstrap/ir/llvm-module-global-name.t:44` | `$ctx->{_method_name} = 'greet';` | **write** |
| `t/bootstrap/ir/llvm-module-global-name.t:52` | `$ctx->{_in_method_body} = 1;` | **write** |
| `t/bootstrap/ir/llvm-module-global-name.t:53` | `$ctx->{_method_class_name} = 'Foo::Bar';` | **write** |
| `t/bootstrap/ir/llvm-module-global-name.t:54` | `$ctx->{_method_name} = 'm';` | **write** |
| `t/bootstrap/ir/llvm-module-global-name.t:60` | `scalar $ctx->{_str_globals}->@*` | read |
| `t/bootstrap/ir/llvm-mainline-die.t:76` | `($ctx->{blocks} // [])->@*` and `$_->{insts}` | read |

The 6 **writes** in `llvm-module-global-name.t` are the same
method-body-context setup that `LLVM.pm:855-858` does — the test is simulating
`LLVM.pm`'s reach-in. Those 6 slots (`_in_method_body`, `_method_class_name`,
`_method_name`) have `ctxW = 0` in the slot table: **nothing inside `Context`
ever sets them.** So whatever writer API the other agent's reach-in removal
produces, this test needs it too, or it cannot set up its fixture at all.

`llvm-mainline-die.t:76` reads `$ctx->{blocks}` where a `blocks` **method
already exists** (`Context.pm:448`) — that one is a one-word change.

`t/bootstrap/leo-graph-equivalence.t:34` does `my $class = ref($ctx) || ''` on
an unrelated `$ctx`; not affected.

### Tests calling Context subs as plain qualified functions

These pin the corresponding subs as `sub` (Finding 6):

| File:line | Call |
|-----------|------|
| `t/bootstrap/ir/repr-to-llvm-type-total.t:10` | `\&Chalk::Target::LLVM::Context::_repr_to_llvm_type` (**code ref**) |
| `t/bootstrap/ir/llvm-repr-to-llvm-type-undef-guard.t:19,32,44,45,46,49` | `Context::_repr_to_llvm_type(...)` |
| `t/bootstrap/ir/node-staleness-kind.t:73` | `Context::_mutable_read_ops()` |
| `t/bootstrap/ir/node-staleness-kind.t:90` | `Context::_pure_descend_ops()` |
| `t/bootstrap/ir/str-is-a-first-class-aggregate.t:32` | `defined &Context::_str_fields` (**symbol-table probe**) |
| `t/bootstrap/ir/str-is-a-first-class-aggregate.t:35,43,60` | `Context::_str_fields()` |
| `t/bootstrap/ir/str-is-a-first-class-aggregate.t:57` | `Context::_str_size_bytes()` |
| `t/bootstrap/ir/str-is-a-first-class-aggregate.t:74` | `Context::_str_type_decl()` |
| `t/bootstrap/ir/strpair-layout-single-source.t:28` | `defined &Context::_strpair_type_decl` (**symbol-table probe**) |
| `t/bootstrap/ir/strpair-layout-single-source.t:31` | `Context::_strpair_type_decl()` |
| `t/bootstrap/ir/strpair-layout-single-source.t:42` | `Context::_strpair_size_bytes()` |
| `t/bootstrap/ir/strpair-layout-single-source.t:49` | `Context::_strpair_fields()` |

Two of these (`defined &...`) probe the symbol table directly. Probe2 test 3
confirms a `sub` inside a `class` body remains visible in the symbol table and
callable as `Pkg::name()`, so these survive **if and only if** those subs stay
`sub`. Converting any of them to `method` breaks the test.

Equivalent sites in `t/` for `LLVM.pm`: `harness-strictness.t:90,:106`
(`_populate_registry_from_mop_class`) and `llvm-mop-direct.t:261`
(`_phaser_body_in_control_order`).

---

## Pre-existing state (baseline, not caused by the conversion)

Recorded so a post-conversion run is not misread.

**`t/bootstrap/ir/repr-to-llvm-type-total.t` is RED at HEAD.**

```
not ok 3 - the four refusal classes each carry their own diagnosis
    not ok 4 - Any: not a value type -- signature vocabulary
# Looks like you failed 1 test of 5.
```

The representation `Any` is in neither `%_REPR_LLVM_TYPE` nor
`%_REPR_NO_MACHINE_TYPE`, so it falls through to the "not a known
representation" arm at `Context.pm:3145` instead of the intended
"not a value type" diagnosis. Unrelated to the class conversion. Filed here
because a conversion run will show this failure and it must not be attributed
to the conversion.

Green at HEAD: `t/bootstrap/ir/llvm-module-global-name.t` (4/4),
`t/bootstrap/codegen-harness/target-hierarchy.t` (6/6, but see Finding 3a on
what those assertions actually prove).

---

## Cross-references

- `docs/plans/2026-08-16-a-gap-is-a-failure.md` — the `GAP:` convention that
  `Context.pm:7-31` documents; the inliner GAP-die at `Context.pm:5777` sits
  inside a `local` extent (Finding 2) and its exception-safety is the risk.
- The cross-graph id-keyed cache collision family — `cache` and
  `_mut_read_memo` (`Context.pm:6007`, `:6010`) are that family's mitigation;
  Finding 2 is where a conversion could silently undo it.
- zhi issue F10 (`_process_if_node`/`_wire_region_phis` duplication) — cited in
  `ElaboratedContext.pm:16-22` as resolved; Finding 5 confirms the file is now
  a pure alias with zero content.
- `docs/plans/2026-06-11-target-ir-architecture-review-resolution.md` —
  Target-layer architecture decisions.

## Probe artifacts

All probes were written to `/tmp/` and are not in the project tree:
`/tmp/probe_class.pl`, `/tmp/probe2.pl`, `/tmp/probe3.pl`, `/tmp/probe4.pl`,
`/tmp/probe5.pl`, `/tmp/probe6.pl`, `/tmp/pl/`. HEAD copies used for counting
are in `scratchpad/head/` (untracked scratch, safe to delete).

## COULD NOT DETERMINE

- Whether the other agent's in-flight reach-in removal introduces new
  construction routes or new fields. Only `@NEED_FLAGS`'s relocation and the
  two new `*_need_flags_from` methods were visible in the working tree at audit
  time; nothing was committed. The 73 reach-ins are still present in both HEAD
  and the working tree, so the removal had not landed when measured.
- Whether the 9 `LLVM.pm`-only slots are intended to become fields on Context
  or to move to a separate prologue-state object. That is the other agent's
  design decision and was not visible.
