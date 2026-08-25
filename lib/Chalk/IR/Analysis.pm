# ABOUTME: Runs the loader's type-inference passes over a decoded graph set.
# ABOUTME: Consumes graphs + class metadata; produces a typed graph set and the MOP.
use 5.42.0;
use utf8;

package Chalk::IR::Analysis;

use Chalk::IR::Serialize::JSON ();
use Chalk::IR::Value;

# WHY THIS IS A SEPARATE MODULE
#
# These passes were previously called from inside
# Chalk::IR::Serialize::JSON::from_json. They are not deserialization: every
# one of them takes GRAPHS (plus class metadata or the MOP) and none touches
# the JSON. An earlier audit described the arrangement as "an
# iterate-to-fixpoint dataflow analysis smeared across a deserializer".
#
# Extracting them makes the phase boundary explicit: from_json decodes, this
# runs the analysis. The move was verified to be safe before it was attempted:
# no pass mutates the decoded JSON, there is no file-scoped mutable state, and
# nothing reads $data in an order-dependent way. See
# docs/plans/2026-08-24-loader-analysis-pipeline.md, slice 1.
#
# THE PASS ORDER BELOW IS LOAD-BEARING AND IS PRESERVED VERBATIM from the
# original. The comments moved with it. Several orderings encode a fixpoint
# dependency (a caller's type is only knowable once its callee is typed), and
# the sequence was arrived at incrementally against the corpus gate. Do not
# reorder without re-running it.
#
# SCOPE (docs/plans/2026-08-24-loader-analysis-pipeline.md): the loader's job
# is a well-typed Chalk IR and nothing else. These passes currently assign
# REPRESENTATIONS; under the plan they move to the type axis, and the
# vocabulary translation becomes the lowering pass's job. This module is where
# that change will happen.

# run($graphs, $classes, $mop_out) -> ($graphs, $mop)
#
# $graphs  — hashref of name => Chalk::IR::Graph, freshly deserialized
# $classes — the decoded `classes` section of the wire, or undef
#
# Returns the same graph set (mutated in place, as the passes have always done)
# and the MOP built by _replay_classes, or undef when the wire declared no
# classes.
sub run ($class, $graphs, $classes = undef) {
    my %graphs = %$graphs;
    my $data   = { classes => $classes };

    # Resolve each direct sub call (dispatch_kind='direct') to its callee graph
    # by name, so the backend can lower the call to the callee's result. A
    # top-level named sub is its own graph (keyed by fully-qualified name), not a
    # MOP class method; the Call carries its callee metaobject on `target`.
    Chalk::IR::Serialize::JSON::_resolve_direct_calls(\%graphs);

    # 4c: a `classes` section (from B::SoN) is replayed into a sealed MOP. Field
    # types must be inferred onto the raw records BEFORE the MOP is sealed, so
    # each declared field carries its type (the backend reads it from the MOP).
    my $mop;
    if (ref $data->{classes} eq 'HASH' && %{ $data->{classes} }) {
        my $classes = $data->{classes};

        # A :param field's type comes from the constructor argument.
        Chalk::IR::Serialize::JSON::_infer_param_field_types($classes, \%graphs);
        # Stamp the field reads that are already typed, then propagate so an
        # ADJUST expression over them (`$val * 2`) carries a repr.
        Chalk::IR::Serialize::JSON::_stamp_field_access_reprs($classes, \%graphs);
        Chalk::IR::Serialize::JSON::_seed_and_propagate_reprs(\%graphs);
        # An ADJUST-only field (no :param, no default) is typed from the value an
        # ADJUST stores into it (Assign(FieldAccess-lvalue, value)). Re-stamp the
        # now-typed field reads (the accessor body's FieldAccess) after.
        if (Chalk::IR::Serialize::JSON::_infer_field_types_from_stores($classes, \%graphs)) {
            Chalk::IR::Serialize::JSON::_stamp_field_access_reprs($classes, \%graphs);
        }

        $mop = Chalk::IR::Serialize::JSON::_replay_classes($classes, \%graphs);

        # Attach each resolved direct Call's callee METAOBJECT as soon as the
        # MOP exists. This used to run at the very end of from_json, on the
        # belief that the repr fixpoint below needed to precede it -- measured
        # wrong: _replay_classes seals the MOP ~30 lines BEFORE the direct-call
        # fixpoint, so the metaobject is available to it.
        Chalk::IR::Serialize::JSON::_attach_call_targets(\%graphs, $mop);
    }

    # Universal repr-inference: seed aggregate/regex reprs and fixpoint-propagate
    # through computed + aggregate-read nodes for EVERY graph (class or not).
    # The backend requires a repr on these nodes to lower them (RC1).
    Chalk::IR::Serialize::JSON::_seed_and_propagate_reprs(\%graphs);

    # Stamp method Calls from the callee's return_repr, then re-propagate: a Call
    # newly types nodes a computed expression consumes (Add over a method-Call
    # result), which the next propagation resolves. This is a FIXPOINT: a method
    # whose BODY consumes a call (`method use_it { $self->a() + 1 }`) has no
    # return_repr until its internal call is stamped AND its body root re-derived,
    # so a caller of use_it can only be stamped on a LATER pass. Loop stamp +
    # propagate until a pass stamps nothing new (zhi 019f5e57). Bounded by the
    # finite number of Call nodes; a graph with no method Calls converges in one
    # pass (stamped==0 immediately).
    while (Chalk::IR::Serialize::JSON::_stamp_method_call_reprs($data->{classes} // {}, \%graphs) > 0) {
        Chalk::IR::Serialize::JSON::_seed_and_propagate_reprs(\%graphs);
    }

    # Direct-call argument binding (F5): a callee's `shift @_` arg-read is typed
    # from the caller's argument repr, then the callee body (and the Call result)
    # re-derive. Fixpoint: a callee reached through a chain is typed once the
    # outer call's arg is known on a prior pass. After seeding, the Call's own
    # result repr is picked up from the callee Return via _resolve_direct_calls'
    # stamp logic, which we re-run to catch calls newly resolvable this pass.
    while (Chalk::IR::Serialize::JSON::_seed_direct_call_arg_reprs(\%graphs) > 0) {
        Chalk::IR::Serialize::JSON::_seed_and_propagate_reprs(\%graphs);
        Chalk::IR::Serialize::JSON::_resolve_direct_calls(\%graphs);
    }
    # The loop stamps a Call's result repr in _resolve_direct_calls AFTER the
    # pass's _seed_and_propagate_reprs already ran, so a consumer of the call
    # result (an `$x = foo(5)` Assign) is still untyped when the loop exits. Run
    # one final propagation so the now-stamped Calls flow into their consumers.
    Chalk::IR::Serialize::JSON::_seed_and_propagate_reprs(\%graphs);

    # 1d: attach the callee METAOBJECT to each resolved direct Call.
    #
    # Call.pm documents `target` as "a MOP::Method/Sub handle ... so codegen can
    # read the callee's graph/params/return-type directly without going through
    # the symbol table at emit time". That is the MOP-shaped contract, and the
    # B::SoN path did not meet it: it set a bare
    # Chalk::IR::Graph, whose own comment explains why -- "a top-level sub is not
    # a MOP class method, so it rides here."
    #
    # Under everything-is-a-class that premise is gone: a file-level sub is a sub
    # of class `main`, and 1a/1b give it a real MOP::Sub. So the callee handle is
    # now available and the flat-graph fallback is no longer the only option.
    #
    # Runs HERE, after _replay_classes has sealed the MOP -- the earlier
    # _resolve_direct_calls passes are part of the repr fixpoint and run before
    # any metaobject exists.

    # Str-context coercions the PRODUCER could not insert. Print(Str...) and
    # StrEq/StrNe(Str, Str) take Str, and the producer wraps a non-Str operand
    # in a Coerce(X -> Str) at its build site -- but only when the operand
    # carries a STAMP there. A method or direct call has no return type until
    # the loader resolves the callee (`say($c->get)`), so the producer sees an
    # unstamped operand, correctly declines to guess, and the operand arrives
    # here typed Int with no coercion in front of it.
    #
    # Runs last, after every repr fixpoint above, because that is the first
    # point the operand's representation is actually known.
    Chalk::IR::Serialize::JSON::_insert_str_coercions(\%graphs);

    # NARROW the Unknowns. The producer writes from_repr 'Unknown' for a Coerce
    # whose operand it could not type -- honestly, since a direct call's result
    # is not typable until the callee's graph exists. By here every repr
    # fixpoint has run and the operand usually IS typed, so the Coerce can be
    # rebuilt against the narrowed type. Runs last, after _insert_str_coercions,
    # so a coercion inserted there is narrowed too.
    Chalk::IR::Serialize::JSON::_narrow_unknown_coercions(\%graphs);

    # THE EXIT INVARIANT -- NOT YET ENFORCED. See
    # _assert_value_nodes_are_typed below for why it is off and what has to
    # happen before it can be turned on.
    #
    # _assert_value_nodes_are_typed(\%graphs);

    # $mop is returned only in list context; scalar context stays \%graphs for
    # the existing single-return callers.
    return (\%graphs, $mop);
}

# _assert_value_nodes_are_typed($graphs)
#
# THE INVARIANT: a Chalk::IR::Value node has a stamp after analysis. A control
# node does not, and must not -- it defines no value, so there is no type for
# it to carry and asking is a category error.
#
# WHY THIS IS CHECKED HERE rather than in Chalk::IR::Value's ADJUST (which is
# how the PRODUCER enforces the same rule, perl5-son SoN::IR::Value): chalk's
# loader constructs every node first (Serialize/JSON.pm:158) and assigns types
# afterwards (:181 and the passes above). An ADJUST would fire on every node
# before any pass had a chance to type it. The producer can use ADJUST because
# it builds a node only once it knows the value; chalk cannot.
#
# WHY IT MATTERS. Once this holds, `defined $node->representation` STOPS
# DISCRIMINATING for value nodes -- it is always true. The nine guards in the
# loader that use it as "already decided" are then asking a question with a
# fixed answer, and must be re-expressed as `_is_narrowed` (committed to
# something, versus still Unknown).
#
# ============================================================================
# CURRENTLY DISABLED. THE INVARIANT DOES NOT HOLD YET -- and turning this on is
# how we found that out, which is the point of writing it before relying on it.
#
# Enabling it drops the corpus gate 218 -> 200, with 18 cases failing.
#
# THE KIND BREAKDOWN THAT WAS RECORDED HERE WAS WRONG, and the way it was wrong
# is worth keeping. It read:
#
#     Phi 21, ArgsSource 18, PadAccess 12, Call 6, Ref 3
#
# Those counts came from loading whole producer JSON files, which carry the
# producer's OWN internals (B::GV::SAFENAME, B::SoN::_cv_is_user_code,
# Exporter::Heavy, ...) alongside the program under test. They described perl's
# guts, not Chalk's corpus. A follow-up census scoped the way the corpus gate
# scopes -- ProgramRunner's not_package= exclusion list -- found:
#
#     PadAccess   3 of 3   (ALL of them; closed, see _stamp_field_access_reprs)
#     ArgsSource  1 of 1   (the `shift @_` read in a sub with args)
#
# Two kinds, not five. `Phi`, `Call` and `Ref` do not appear in user code at
# all at this sample size. And the cascade that breakdown implied does not
# exist: the DOWNSTREAM count (untyped node with an untyped input) is ZERO --
# every untyped node is its own root, so there is no single hole to find whose
# closure fixes the rest.
#
# An even earlier 7-program census suggested the invariant already held. It did
# not. Between them the lesson is the same twice: a sample that is not scoped
# the way the gate is scoped will mislead in whichever direction it happens to
# be unrepresentative.
#
# MEASURED AGAINST THE FULL 218-CASE CORPUS (2026-08-25), which is what the
# eight-program caveat above asked for. Sixteen untyped Value nodes in total:
#
#     Phi          7   DOWNSTREAM   main::__PROGRAM__
#     ArgsSource   6   root         main::f, main::id
#     Call         2   root         main::__PROGRAM__
#     Ref          1   root         main::__PROGRAM__
#
# So the real work was NINE root nodes in three kinds. The seven Phis are all
# downstream -- untyped because their inputs are -- and should resolve when the
# roots do rather than needing rules of their own.
#
# ARGSSOURCE IS CLOSED (perl5-son 714ec0e), taking 6 of the 9 roots with it.
# Re-measured after: SIXTEEN -> TEN untyped, THREE roots left (Call 2, Ref 1),
# and ArgsSource does not appear at all.
#
# The fix was to stamp `@_` as `Array` at the producer. It defaulted to
# `Unknown`, which claims inference FAILED when nothing had ever asked: `@_` is
# an array of scalars structurally, for every sub, with no inference required.
# (`List` would be one level too wide -- that is the flattening notion, and the
# backend refuses it as signature vocabulary.)
#
# An earlier note here argued AGAINST stamping it, on two grounds. Both were
# wrong, and the record is kept because the reasoning is the reusable part:
#
#   - "Array[Scalar] does not lower, so the stamp is useless." True about the
#     ELEMENT, irrelevant to the CONTAINER. %Array* has had a machine encoding
#     all along, and nothing reads ArgsSource as a value -- `shift` and `$_[0]`
#     mint their own nodes, typed from the callsite. Only `my @a = @_` needs
#     the element type, and that shape stays a GAP.
#   - "It would paper over the real defect: a parameter read should not route
#     through @_ as a MEMORY READ (Parameter.pm)." That defect is real and
#     already fixed for the case it covers -- a signature sub mints Parameter
#     nodes and has no ArgsSource at all. `shift` is not that case: it MUTATES
#     the list, which is a genuine array operation, so ArgsSource is the right
#     node there and typing it is not papering over anything.
#
# THIS IS A REAL GAP IN THE LOADER'S TYPING, not a bad assertion. Each of the
# five is a node that DEFINES a value and reaches lowering with no type, which
# is exactly the GIGO condition the analysis pipeline exists to remove
# (docs/plans/2026-08-24-loader-analysis-pipeline.md). `PadAccess` in a
# `:reader` accessor body is the clearest instance: `Pair::left` returns a pad
# read that nothing types.
#
# TO ENABLE: close the three remaining roots, or narrow the assertion to the
# kinds that are genuinely covered and widen it as each is fixed. PadAccess and
# ArgsSource are closed. Call (2) and Ref (1) are unexamined, and the 7 Phis
# should follow from them without rules of their own -- worth re-measuring
# rather than assuming, since every census this session has corrected the one
# before it.
#
# Do NOT enable it by weakening it to "warn" -- a contract nothing enforces is
# the state this function was written to end.
# ============================================================================
sub _assert_value_nodes_are_typed ($graphs) {
    my @untyped;
    for my $gname (sort keys %$graphs) {
        my $g = $graphs->{$gname} or next;
        for my $node ($g->nodes->@*) {
            next unless $node isa Chalk::IR::Value;
            next if defined $node->stamp;
            push @untyped, sprintf('%s in %s (%s)',
                $node->operation, $gname, $node->id);
            last if @untyped >= 5;   # naming five is enough to diagnose
        }
        last if @untyped >= 5;
    }
    return unless @untyped;

    die "IR: analysis finished with untyped Value node(s) -- every node that "
      . "DEFINES a value must carry a type by the end of the pipeline, so "
      . "lowering can rely on it: @untyped\n";
}

1;
