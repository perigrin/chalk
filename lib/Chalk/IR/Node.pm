# ABOUTME: Base class for all IR nodes in the Chalk Sea of Nodes representation.
# ABOUTME: Provides id, use-def chains, content_hash, stamp, and compat_class fields.
use 5.42.0;
use utf8;
use experimental 'class';

# The deprecation category for `representation` / `set_representation`.
#
# TWO GATES, AND BOTH ARE LOAD-BEARING.
#
# `warnings::register` gives the category, so a scope mid-migration can say
# `no warnings 'Chalk::IR::Node'` to silence a file it has not reached yet.
# Verified: that suppression works.
#
# But the category is ON by default under `use 5.42.0`, and these methods are
# called from everywhere. MEASURED: with the warning ungated, ONE ordinary test
# file (ir/a-method-takes-arguments.t) emits 1438 deprecation lines. That is not
# a warning anyone reads; it is a wall that hides the diagnostics underneath it,
# and this project treats non-pristine test output as a failure rather than as
# noise to skim.
#
# So the warning is additionally gated on CHALK_WARN_DEPRECATED_REPR being set.
# Default silent, opt-in loud:
#
#     CHALK_WARN_DEPRECATED_REPR=1 prove -Ilib t/some/file.t
#
# which is what makes the migration incremental -- turn it on, fix what it
# names, move to the next file -- rather than one commit that must touch ~1700
# sites at once. The env gate goes away with the last call site; the category
# outlives it only long enough to prove the last one is gone.
package Chalk::IR::Node { use warnings::register; }

# Read once at load: this is checked on a hot path (every stamp read in the
# compiler) and a per-call %ENV lookup would be a real cost for a diagnostic
# that is off in every normal run.
my $_WARN_DEPRECATED_REPR = $ENV{CHALK_WARN_DEPRECATED_REPR} ? 1 : 0;

class Chalk::IR::Node {

    # Stable content-based ID for the node
    field $id :param :reader;

    # Producer nodes - nodes that produce values consumed by this node
    field $inputs :param :reader = [];

    # Consumer nodes - nodes that consume values produced by this node
    # This is mutable to allow building the graph
    field $consumers :reader = [];

    # The node's TYPE. Also reachable as `representation` -- see the deprecated
    # alias at the bottom of this class; they are the same storage.
    #
    # `:param` NOTE. A stamp can be supplied at CONSTRUCTION, which the
    # representation field never allowed. Since the two are now one field, a
    # constructor-supplied stamp also pre-sets the representation -- and NINE
    # loader passes are guarded by `defined $node->representation` meaning
    # "already decided", so such a node is INVISIBLE TO INFERENCE and bypasses
    # the %LOWERABLE_STAMP filtering the wire path applies.
    #
    # Measured: nothing in lib/ passes `stamp =>` at construction (zero sites),
    # so this is latent, not live. It is left in place because three tests do
    # use it (t/bootstrap/ir-node-base.t:35, ir-node-data.t:18,25) and removing
    # it would break them for no production gain. Do not start using it in
    # production code without deciding what it means for inference.
    field $stamp        :param :reader = undef;

    # Optional compat_class overrides the result of class() for back-compat
    field $compat_class :param :reader = undef;

    # Effect-chain predecessor when this node appears as a statement-position
    # side effect (bare Call, bare Assign, etc.). Set by the Block control-
    # chain fixup pass via set_control_in(); undef for nodes in pure-data
    # position. Not part of content_hash: side-effect vs pure-data uses of
    # the same content (e.g. `foo()` as statement vs as expression) should
    # still hash-cons to the same node; control_in is a per-use decoration.
    field $control_in :reader = undef;

    # Per-node scheduler interpretation, populated lazily by the scheduler
    # via set_schedule_data(). Holds a Chalk::Scheduler::ScheduleMeta
    # subclass instance whose dialect (EagerPinning, GCM, ...) matches the
    # scheduler that produced the current Schedule. Excluded from
    # content_hash for the same reason as control_in: it is a per-use
    # decoration, not a structural property of the node's content.
    field $schedule_data :reader = undef;

    # NO SEPARATE `representation` FIELD. It was folded into `stamp` above:
    # `representation`/`set_representation` are a deprecated ALIAS for
    # `stamp`/`set_stamp` (see the bottom of this class for why, and for the
    # conditions under which the alias is deleted).
    #
    # The machine vocabulary that field carried is recorded here because it is
    # still what the BACKEND expects to read, until the lowering pass exists to
    # produce it: 'Boolean' (i1), 'Int' (i64), 'Num' (double/f64),
    # 'Str' ({ptr,len,encoding}), 'Undef'/'Slot' ({defined,payload}),
    # 'Array' ({len,cap,Slot*}), 'Hash' (linear-scan table),
    # 'ArrayRef'/'HashRef' (i8* to the boxed aggregate),
    # 'Object' (i8* to {vtable*, Slot...}).
    #
    # Note 11 of those 12 names are ALSO type-lattice members -- which is what
    # makes the alias sound. `Slot` is the sole exception and is assigned at
    # exactly one site; see docs/plans/2026-08-24-there-should-be-no-representation-field.md.
    #
    # The exclusion from content_hash still holds and now applies to `stamp`:
    # two nodes with identical content (same literal, same operation, same
    # inputs) must hash-cons to one node regardless of what type is later
    # assigned. Coerce nodes bridge between representations on edges.

    # Add a consumer to this node's consumer list
    method add_consumer($node) {
        push $consumers->@*, $node;
    }

    # Remove a consumer from this node's consumer list
    method remove_consumer($node) {
        my $target_id = $node->id();
        $consumers->@* = grep { $_->id() ne $target_id } $consumers->@*;
    }

    # Abstract method - subclasses must implement
    method operation() {
        die ref($self) . " must implement operation()";
    }

    # Is this node FIXED — does it have an effect that pins it to a point in the
    # control chain, rather than being a pure value free to float?
    #
    # A PROPERTY OF THE TYPE, deliberately. The same question is answered today
    # by %STATEMENT_EFFECT_OPS, a list of ten op NAMES held beside the classes,
    # consulted by string comparison (96 such comparisons over 19 ops across
    # lib/). That registry is already incomplete: `Unwind` — a `die`, which
    # ABORTS — is absent from it, and the backend compensates with hand-written
    # `eq 'Unwind'` special cases.
    #
    # The prior-art survey (docs/research/2026-08-13-branch-merge-prior-art.md)
    # found that production Sea-of-Nodes compilers make this a type property.
    # In Graal an effectful node IS a FixedNode, which is why its
    # diamond-collapse test degenerates to "is the arm empty?" — the
    # side-effect question is subsumed structurally and never asked. Chalk
    # cannot take that shortcut while the answer lives in a name list a
    # consumer must remember to consult.
    #
    # Default FALSE: a node is pure unless its class says otherwise. That is the
    # safe default for the registry's PURPOSE (control-chain threading, which
    # only ever needs to include more) but NOT for a collapse pass, which needs
    # the answer to be complete — which is why the accompanying test pins every
    # registry entry against this method rather than trusting either alone.
    method is_fixed() { return false }

    # May a cached SSA ref for this node go STALE across a store?
    #
    # A PROPERTY OF THE TYPE, for the same reason is_fixed is. The same
    # question is answered today by %MUTABLE_READ_OPS and %PURE_DESCEND_OPS in
    # Target/LLVM/Context.pm — two op-name lists whose `if/elsif` leaves a
    # THIRD bucket implicit, so an op in neither list answers "no" by falling
    # off the end.
    #
    #   mutable_read — reads a mutable location (a pad slot, an aggregate
    #                  element, an object field, a stash entry). Its lowered
    #                  value is program-point-dependent: a later store changes
    #                  what an identical load returns. Answer YES, stop.
    #   transparent  — my value is stale exactly when an input's is, so the
    #                  answer comes from my inputs. Descend.
    #   opaque       — a fixed SSA value at a single program point. Either an
    #                  effect that executes once at its control position, or a
    #                  value with no mutable provenance. Answer NO, stop.
    #
    # NOTE the middle bucket is TRANSPARENCY, not purity. Coerce, Interpolate
    # and TernaryExpr are all in it and none is pure in any ordinary sense.
    # What they share is that staleness passes THROUGH them.
    #
    # DEFAULT mutable_read, and the direction is the whole point. Under the
    # registry pair the implicit default was "opaque" — a new op silently
    # answered "no, this cannot go stale", and a wrong NO serves a stale SSA
    # ref across a store (the whole-branch review C1/C2 miscompile class). A
    # wrong `mutable_read` only re-lowers a node that did not need it. The
    # unsafe direction must cost performance, not correctness.
    #
    # is_fixed defaults FALSE for the opposite reason and that is not an
    # inconsistency: its registry's purpose only ever needs to include more,
    # while this one's needs to be complete.
    method staleness_kind() { return 'mutable_read' }

    # Does each occurrence of this op get its OWN node, or do textually
    # identical occurrences share one?
    #
    #   per_call    — every make() allocates a fresh node with a counter id.
    #                 A distinct side effect, allocation, or control position:
    #                 two identical Prints at different program points are two
    #                 effects, and hash-consing them drops one (019eb6ff #1).
    #   hash_consed — identical content IS the identical node. A pure value.
    #
    # A PROPERTY OF THE TYPE, like is_fixed and staleness_kind. make() answers
    # it today in five structurally identical branches, from four tables
    # (%ROUTED_CFG, %STATEMENT_EFFECT_OPS, %ALLOC_OPS, and membership in
    # %DATA_CLASSES) plus three ops hardcoded ahead of all of them (Phi,
    # VarDecl, ListAssign). Measured: 62 hash_consed, 19 per_call.
    #
    # DEFAULT per_call — the conservative direction, on the same principle as
    # staleness_kind. A class that declares nothing gets its own node per
    # occurrence: that costs a missed dedup. The opposite default would share
    # one node between two occurrences of an op nobody classified, which
    # silently drops the second effect. Losing an optimisation beats losing a
    # statement.
    #
    # LIMIT, measured and deliberate: for Start/Return/Unwind identity depends
    # on the ENTRY POINT, not on the type — make() hash-conses them while
    # make_cfg() allocates fresh (NodeFactory.pm:110-115 documents this as
    # intent). This describes make(). make_cfg() is a separate constructor
    # whose contract is "always fresh" for every op it accepts, and a node
    # built through it is per-call whatever its type says. That exception is
    # pinned by t/bootstrap/ir/node-identity-kind.t so a later unification has
    # to preserve it or change it on purpose.
    #
    # A `sub`, NOT a `method`, and that is load-bearing: make() must know the
    # answer BEFORE it constructs anything, because a node's id is fixed at
    # new() and there is no set_id. A `method` cannot be called on a class name
    # ("Cannot invoke method ... on a non-instance") and a feature-class
    # instance cannot be faked to stand in for one ("Attempt to bless into a
    # class"), so an instance method could not be consulted at the point that
    # needs it. A plain sub in a class block is a class method, inherits
    # through :isa like any other, and is findable via can().
    sub identity_kind { return 'per_call' }

    method class() {
        return $compat_class if defined $compat_class;
        return $self->operation();
    }

    # Serialize inputs to a list of ID strings for content_hash.
    # Handles undef, nested arrayrefs, and plain node inputs.
    method _serialize_inputs() {
        my @parts;
        for my $input ($self->inputs()->@*) {
            if (!defined $input) {
                push @parts, 'undef';
            } elsif (ref($input) eq 'ARRAY') {
                my @ids = map { defined($_) ? $_->id() : 'undef' } $input->@*;
                push @parts, '[' . join(',', @ids) . ']';
            } else {
                push @parts, $input->id();
            }
        }
        return @parts;
    }

    method content_hash() {
        return join('|', $self->operation(), $self->_serialize_inputs());
    }

    # Late-binding setter for the per-node scheduler interpretation.
    # Called by the scheduler as it walks the graph and decides what
    # surface syntax each control-affecting node should emit.
    method set_schedule_data($meta) {
        $schedule_data = $meta;
        return;
    }

    # Late-binding setter for the stamp (type-lattice hint carried from
    # B::SoN). A loop header Phi's stamp is only knowable after the body
    # walk computes the back-edge value's stamp, so the producer patches
    # it in post-construction, mirroring set_control_in/set_representation.
    method set_stamp($new_stamp) {
        $stamp = $new_stamp;
        return;
    }

    # Late-binding setter for the effect-chain predecessor.
    # Maintains the bidirectional use-def edge by adjusting consumer
    # registration on the old and new predecessors. Called by the
    # Block control-chain fixup pass in Perl::Actions when this node
    # appears as a statement-position side effect.
    method set_control_in($ctrl) {
        if (defined $control_in) {
            $control_in->remove_consumer($self);
        }
        $control_in = $ctrl;
        if (defined $ctrl) {
            $ctrl->add_consumer($self);
        }
        return;
    }

    # ---------------------------------------------------------------------
    # DEPRECATED ALIAS. `representation` and `set_representation` are the same
    # storage as `stamp`/`set_stamp` -- ONE FIELD, TWO NAMES.
    #
    # WHY: the loader is moving onto the type axis
    # (docs/plans/2026-08-24-loader-analysis-pipeline.md, slice 3). The backend
    # reads `representation` at 43 sites and branches on it 94 times, and the
    # lowering pass that would produce real machine representations does not
    # exist yet -- so the field cannot simply stop being written.
    #
    # An ALIAS rather than a dual-write, deliberately: a dual-write stores the
    # same fact twice and the two copies can rot apart, which this project has
    # a documented instance of (CLAUDE.md: `body` arrayrefs, 15 reader sites
    # outstanding). One field cannot diverge from itself.
    #
    # THE ALIAS IS SILENT ON PURPOSE. No deprecation warning: it would fire on
    # every one of the backend's 43 reads in every test run, which is noise
    # standing in for a check the deletion already performs exactly. The
    # enforcement is that DELETING these two methods breaks compilation at
    # every remaining caller.
    #
    # NOTHING WILL REMIND ANYONE THIS EXISTS. Removal is a named first step of
    # the lowering-pass work; see the DESIGNED section of
    # docs/architecture/ir-and-lowering.md.
    #
    # WHY IT CANNOT BE THE END STATE: `Unknown` is the correct TYPE for an
    # un-narrowed node and an invalid REPRESENTATION for the same node --
    # _repr_to_llvm_type dies on it, and NINE loader passes treat a node that
    # has one as already-typed. One value, right on one axis and poison on the
    # other. The two axes must become separate fields again once the lowering
    # pass can produce the second one.
    #
    # THE ALIAS IS DESTRUCTIVE IN ONE DIRECTION -- `set_representation`
    # OVERWRITES the type rather than naming it:
    #
    #     set_stamp('Int')           -> stamp=Int
    #     set_representation('Slot') -> stamp=Slot     the Int TYPE would be gone
    #
    # Every write in lib/ passes a name that is ALSO a lattice type, so the
    # alias is wrong-vocabulary rather than lossy, and a `->stamp` reader
    # cannot be poisoned. Pinned by t/bootstrap/ir/stamp-alias-preconditions.t,
    # which fails if a non-lattice name is written again.
    # hazard RETURNING rather than documenting a live one.
    #
    # ---------------------------------------------------------------------
    # DEPRECATED. NEW CODE MUST USE `stamp` / `set_stamp`.
    #
    # These two are a transitional read/write alias for the SAME storage, kept
    # only so the ~111 existing `->representation` call sites in lib/ keep
    # working while they are migrated. Measured at the time of writing:
    #
    #     ->representation   111 reads      ->stamp        12
    #     set_representation  32 writes     set_stamp       6
    #
    # so the deprecated spelling is still the majority and cannot simply be
    # deleted. It is not merely a style preference: the name is WRONG about
    # which axis it names. A stamp is a TYPE (`Unknown` is a legitimate value);
    # a representation is a MACHINE ENCODING (`Unknown` has none, and
    # _repr_to_llvm_type dies on it). Calling the type axis by the encoding
    # axis's name is what lets a value that is correct on one axis be read as
    # poison on the other -- see the paragraphs above for the concrete case.
    #
    # PLANNED, in this order, and deliberately NOT done together:
    #   1. this notice                       <- you are here
    #   2. a `warnings::register` deprecation warning on both methods, silent
    #      by default so no existing run becomes noisy
    #   3. migrate the call sites, then restore pristine test output
    #   4. delete these two methods
    #
    # Step 2 is separated from step 1 because turning on a warning across 143
    # call sites at once floods every test run, and this project treats
    # non-pristine test output as a failure rather than as noise to skim. The
    # warning lands only when the migration is ready to absorb it.
    # ---------------------------------------------------------------------
    method representation() {
        warnings::warnif('Chalk::IR::Node',
            'representation() is deprecated; use stamp() -- it names the TYPE '
          . 'axis, which is what this returns')
            if $_WARN_DEPRECATED_REPR;
        return $stamp;
    }
    method set_representation($repr) {
        # The write is the more dangerous direction: it OVERWRITES the type
        # rather than naming it, so a non-lattice name here destroys a real
        # type. See the paragraphs above.
        warnings::warnif('Chalk::IR::Node',
            'set_representation() is deprecated; use set_stamp() -- it writes '
          . 'the TYPE axis, and a machine-encoding name here destroys the type')
            if $_WARN_DEPRECATED_REPR;
        $stamp = $repr;
        return;
    }
}
