# ABOUTME: Runs the loader's type-inference passes over a decoded graph set.
# ABOUTME: Consumes graphs + class metadata; produces a typed graph set and the MOP.
use 5.42.0;
use utf8;

package Chalk::IR::Analysis;

use Chalk::IR::Serialize::JSON ();

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

    # $mop is returned only in list context; scalar context stays \%graphs for
    # the existing single-return callers.
    return (\%graphs, $mop);
}

1;
