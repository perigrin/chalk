# ABOUTME: Serialize/deserialize Chalk::IR::Graph instances to/from JSON.
# ABOUTME: Provides to_json(\%named_graphs) and from_json($json_string) as exportable subs.

package Chalk::IR::Serialize::JSON;

use 5.42.0;
use utf8;
use Exporter 'import';

our @EXPORT_OK = qw(to_json from_json);

use JSON::PP ();
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Coerce;   # _insert_str_coercions builds these directly
use Chalk::Grammar::Perl::TypeLibrary;   # is_subtype: the join lattice

# CFG node operations — these carry control tokens and are never hash-consed.
my %CFG_OPS = map { $_ => 1 } qw(Start Return Unwind If Proj Region Loop);

# B::SoN carries type info as a `stamp` drawn from the shared lattice (see
# Chalk::Grammar::Perl::TypeLibrary, which is canonical); Chalk's backend
# requires an explicit `representation`. The names agree, so the only question
# at this boundary is which stamps the backend can lower.
# The stamp names that are also representation names. This is a WHITELIST, not
# a translation: the two vocabularies agree name-for-name, and what this set
# carries is which stamps the backend can actually lower. A stamp outside it
# (Scalar, List, DualVar, a ref type) leaves the representation unset so
# _require_repr reports an honest GAP instead of mislowering.
# The wire stamps that may enter the representation field. This is a filter on a
# SHARED field, not a statement about the lattice: `stamp` and `representation`
# are one field under the transitional alias (Chalk::IR::Node), so a name
# admitted here is simultaneously claimed as a machine encoding.
#
# `Unknown` is excluded and MUST STAY excluded. It is not merely unlowerable --
# it is a poison value in this field, in two ways at once. It blocks the
# inference that would have narrowed it (the loader's guards read a present
# repr as "already decided"; _is_narrowed below softens that but the passes
# still have nothing to narrow FROM), and any node still holding it at machine
# type selection dies in _repr_to_llvm_type: "the pessimistic top: INFERENCE
# never determined a type for this value."
#
# That is also the sharpest argument that the alias cannot be the end state:
# `Unknown` is the CORRECT type for an un-narrowed node and an INVALID
# representation for that same node. One value, right on one axis and poison on
# the other, is what a single shared field cannot express -- see
# docs/plans/2026-08-24-loader-analysis-pipeline.md.
#
# `ArrayRef`/`HashRef` are admitted (slice 3b). Both already have machine
# encodings in %_REPR_LLVM_TYPE (`i8*`, a boxed aggregate pointer), so dropping
# them was an omission in the original six-name list rather than a deliberate
# exclusion. Measured over 12 programs, they are 9 of the 86 stamps the producer
# emits; `Unknown` is another 9.
#
# `Array`/`Hash` are admitted too, and they are the CONTAINERS -- `%Array*`
# ({i64, i64, %Slot*}) and `%Hash*` -- not the ArrayRef/HashRef references that
# point at them. Both have had machine encodings all along
# (`Context.pm:3529-3530`); what was missing was a producer that emitted them.
# An earlier note here recorded that the remaining lattice names "are never
# emitted at all", which was true when measured and is now false for these two:
# perl5-son 86d7f73 stamps an aggregate SIGNATURE PARAMETER from its sigil, so
# `sub f($x, @rest)` sends @rest as Array and `sub g($x, %opt)` sends %opt as
# Hash. Dropping them here would discard the only type information that end can
# provide about a slurpy.
#
# Note the asymmetry with the element type: the CONTAINER lowers, but
# `Array[Scalar]`'s ELEMENT does not, for want of a boxed value representation
# (docs/architecture/ir-and-lowering.md section 5). Admitting `Array` types the
# container; it does not make an arbitrary element read lowerable.
my %LOWERABLE_STAMP = map { $_ => 1 }
    qw(Int Num Str Boolean Undef Object ArrayRef HashRef Array Hash);

# _is_narrowed($repr) — has this node COMMITTED to a representation?
#
# Not the same question as `defined $repr`, and the difference is the whole
# reason this exists. `Unknown` is how the producer says it could not type a
# value; it is a present answer that answers nothing. A pass asking "was this
# already decided, so I should leave it alone?" must say no to it.
#
# The two spellings agree today only because the wire-stamp seed below gates on
# %LOWERABLE_STAMP, which drops `Unknown` and leaves the field undef. That gate
# is removed in slice 3b (docs/plans/2026-08-24-loader-analysis-pipeline.md),
# at which point `defined` would start reading the producer's admission of
# ignorance as a committed type -- silently, since every such guard would just
# stop doing its work. The measured casualty is the OOB->Slot fix below: it
# would stop firing and corpus R9 would miscompile.
#
# The producer draws the same line (perl5-son FromOptree.pm:3100). It holds a
# Stamp object and so tests `$stamp->type ne 'Unknown'`; this field holds a
# plain string, so the test is against the string. If the field ever becomes a
# Stamp here too, this is the one site that changes.
sub _is_narrowed ($repr) {
    return defined $repr && $repr ne 'Unknown';
}

# -----------------------------------------------------------------------
# _extract_fields($node, \%id_remap) — returns a hashref of extra fields
# for nodes that carry them, or undef if no extra fields.
# id_remap is needed for Phi whose region field holds a node reference.
# -----------------------------------------------------------------------
sub _extract_fields ($node, $id_remap) {
    my $op = $node->operation;

    if ($op eq 'Constant') {
        return {
            const_type => $node->const_type,
            value      => defined $node->value ? "${\$node->value}" : undef,
        };
    }
    if ($op eq 'Call') {
        return {
            dispatch_kind => $node->dispatch_kind,
            name          => $node->name,
            # Constructor calls (name='new') carry the :param name list; losing
            # it silently re-lowers with no bound params (branch-review I3).
            param_names   => [ ($node->param_names // [])->@* ],
            # Method-dispatch calls name their statically-known class
            # (019eb42a MOP-direct); losing it makes a reloaded call
            # un-lowerable and changes its content hash.
            (defined $node->class_name ? (class_name => $node->class_name) : ()),
            # paren_form is part of content_hash (Call.pm) -- losing it would
            # change a reloaded call's identity/hash-consing behavior relative
            # to the graph that produced it.
            paren_form => $node->paren_form,
        };
    }
    if ($op eq 'Phi') {
        return { region => $id_remap->{ $node->region->id } };
    }
    if ($op eq 'Proj') {
        return { index => $node->index };
    }
    if ($op eq 'PadAccess') {
        return { targ => $node->targ, varname => $node->varname };
    }
    if ($op eq 'FieldAccess') {
        return { field_index => $node->field_index, field_stash => $node->field_stash };
    }
    if ($op eq 'Parameter') {
        return {
            # The INDEX is the identity: a parameter is a value identified by
            # POSITION, and two reads of parameter 0 are one node. The name is
            # debug information; the sigil is what types it, and a slurpy is
            # NOT always an array -- `sub f(%h)` is a hash.
            index => $node->index,
            name  => $node->name,
            sigil => $node->sigil,
        };
    }
    if ($op eq 'EntryDef') {
        return {
            stash_name => $node->stash_name,
            sigil      => $node->sigil,
            var_name   => $node->var_name,
        };
    }
    if ($op eq 'CompoundAssign') {
        return { op => $node->op };
    }
    if ($op eq 'PostfixDeref') {
        return { sigil => $node->sigil };
    }
    if ($op eq 'RegexMatch') {
        return {
            pattern => $node->pattern,
            flags   => $node->flags,
        };
    }
    if ($op eq 'RegexSubst') {
        return {
            pattern     => $node->pattern,
            replacement => $node->replacement,
            flags       => $node->flags,
        };
    }
    if ($op eq 'RegexCapture') {
        return { n => $node->n };
    }
    if ($op eq 'EnvRead') {
        return { key => $node->key };
    }
    if ($op eq 'VarDecl') {
        return { scope => $node->scope };
    }
    if ($op eq 'Coerce') {
        return {
            from_repr => $node->from_repr,
            to_repr   => $node->to_repr,
        };
    }
    return undef;
}

# -----------------------------------------------------------------------
# This is the cross-repo walk-order contract; the corpus gate enforces it.
# perl5-son's SoN::Serialize::JSON carries a duplicated copy of this function
# (deliberately — the repos are divorced); the gate keeps them honest.
#
# _all_nodes_topo($graph_or_nodes) — return all nodes in topological order.
# Accepts either a Chalk::IR::Graph (calls ->nodes) or a plain arrayref of
# already-reachable nodes (a caller that computed its own reachable set via
# a full inputs+consumers BFS, e.g. a producer whose graph was never
# incrementally merge()'d into a Graph's own membership cache). Graph->nodes
# does a DFS over inputs[] only; Phi nodes reference a region via a separate
# field (not inputs[]), so Region may appear after Phi in the base list.
# This function re-sorts to ensure Phi region references are always
# serialized before their Phi nodes.
# -----------------------------------------------------------------------
sub _all_nodes_topo ($graph_or_nodes) {
    my $base = ref($graph_or_nodes) eq 'ARRAY'
        ? $graph_or_nodes
        : $graph_or_nodes->nodes;

    # Collect any Phi region nodes AND control_in-linked nodes not already in
    # the base list. Graph::nodes()'s membership cache is seeded by
    # merge()/_seed() and its consumer walk is filtered to cached members
    # (Graph.pm's `in_cache` check) -- a node reachable ONLY via a control_in
    # edge (produce-time control: set_control_in registers the use-def edge
    # via add_consumer, but never merge()s the node into the graph's own
    # cache) is invisible to that walk and would silently vanish from the
    # serialized output. Two distinct shapes need adding:
    #   (a) a node whose control predecessor is missing (walk control_in
    #       BACKWARD from every base node -- e.g. a void statement-effect
    #       Call reached only via a Return's control_in); and
    #   (b) a node that is itself missing because its only inbound edge is
    #       ITS OWN control_in pointing at an already-reachable node (e.g. a
    #       loop condition whose control_in is the Loop, but nothing's
    #       inputs() reference the condition) -- walk FORWARD via consumers()
    #       and keep any consumer whose control_in points back at the node
    #       being walked.
    # Fixpoint both directions together (an added node can itself expose
    # further control_in-only neighbors) until nothing new is found.
    my %seen = map { $_->id => 1 } $base->@*;
    my @extra;
    my @frontier = $base->@*;
    while (@frontier) {
        my @next_frontier;
        for my $node (@frontier) {
            if ($node->operation eq 'Phi') {
                my $region = $node->region;
                if (defined $region && !$seen{ $region->id }++) {
                    push @extra, $region;
                    push @next_frontier, $region;
                }
            }
            # (a) backward: this node's own control predecessor.
            if ($node->can('control_in') && defined $node->control_in) {
                my $ctrl = $node->control_in;
                if (!$seen{ $ctrl->id }++) {
                    push @extra, $ctrl;
                    push @next_frontier, $ctrl;
                }
            }
            # (b) forward: a consumer whose control_in IS this node.
            if ($node->can('consumers')) {
                for my $c ($node->consumers->@*) {
                    next unless blessed($c);
                    next unless $c->can('control_in') && defined $c->control_in
                        && $c->control_in->id eq $node->id;
                    next if $seen{ $c->id }++;
                    push @extra, $c;
                    push @next_frontier, $c;
                }
            }
        }
        @frontier = @next_frontier;
    }

    # Always re-sort via DFS post-order so that Phi regions are guaranteed
    # to precede their Phi nodes (region is a predecessor, not in inputs[]).
    my @all = grep { blessed($_) } ($base->@*, @extra);
    my %visited;
    my %in_progress;
    my @order;

    # Predecessors of a node are its inputs plus, for Phi, its region, plus
    # (control-aware topo) its control_in edge when it has one. A node whose
    # ONLY inbound edge is control_in (e.g. a void statement-effect Call with
    # no data consumer) has no ordering constraint from inputs() alone and
    # could otherwise be emitted AFTER whatever reads it via control_in (e.g.
    # a Return whose control_in it is) -- a genuine forward reference the
    # loader would reject. Adding control_in as a predecessor here forces it
    # to be visited (and thus emitted) before its control_in consumer,
    # exactly like any other producer edge. control_in never closes a cycle
    # back through itself the way a loop Phi's backedge does (it is a
    # straight-line control chain: Start -> effect -> effect -> ... ->
    # Return/Loop), so no cycle-cut exclusion is needed here.
    #
    # A LOOP header Phi's second input (inputs[1], the back-edge value) is
    # the cycle-closing edge: it necessarily forward-references in any
    # serialization order (the loader defer-patches it via set_backedge once
    # every node exists). Treating it as an ordinary predecessor to visit
    # eagerly picks whichever side of the Phi<->backedge cycle the caller's
    # (unordered) input list happens to reach first: if the Phi is visited
    # before the value that reads it (e.g. an Add computing the next
    # iteration), descending into the backedge hits that Add's in-progress
    # cycle guard and lets the Add finish -- and get appended -- BEFORE the
    # Phi, producing a genuine (non-sanctioned) forward reference. Exclude
    # the backedge from a loop Phi's predecessors so only its init input
    # (inputs[0]) and region are visited eagerly, mirroring the
    # pre-unification SoN::IR::Graph::nodes() cycle-cut. A MERGE Phi (region
    # is a Region, not a Loop) has no such cycle and keeps both inputs.
    my $predecessors = sub ($n) {
        my @in = $n->inputs->@*;
        if ($n->operation eq 'Phi' && defined $n->region
                && $n->region->operation eq 'Loop') {
            @in = ($in[0]);
        }
        my @preds = grep { defined $_ && blessed($_) } @in;
        if ($n->operation eq 'Phi' && defined $n->region) {
            push @preds, $n->region;
        }
        if ($n->can('control_in') && defined $n->control_in) {
            push @preds, $n->control_in;
        }
        return @preds;
    };

    my $visit;
    $visit = sub ($n) {
        return unless blessed($n);
        return if $visited{ $n->id };
        return if $in_progress{ $n->id };   # cycle guard
        $in_progress{ $n->id } = 1;
        for my $pred ($predecessors->($n)) {
            $visit->($pred);
        }
        delete $in_progress{ $n->id };
        $visited{ $n->id } = 1;
        push @order, $n;
    };

    for my $node (@all) {
        $visit->($node);
    }

    return \@order;
}

# -----------------------------------------------------------------------
# _serialize_graph($graph) — returns a Perl data structure for one graph.
# -----------------------------------------------------------------------
sub _serialize_graph ($graph) {
    my $topo_nodes = _all_nodes_topo($graph);

    # Build positional ID remap: node->id => positional index (0, 1, 2, ...)
    my %id_remap;
    my $pos = 0;
    for my $node ($topo_nodes->@*) {
        $id_remap{ $node->id } = $pos++;
    }

    # Emit each node
    my @nodes;
    for my $node ($topo_nodes->@*) {
        my @inputs = map { $id_remap{ $_->id } } grep { blessed($_) } $node->inputs->@*;
        my $fields = _extract_fields($node, \%id_remap);

        my %entry = (
            id     => $id_remap{ $node->id },
            op     => $node->operation,
            inputs => \@inputs,
        );
        $entry{fields} = $fields if defined $fields;
        # Produce-time control: emit the control_in edge as its own wire key
        # so from_json can decode it back onto control_in directly, instead
        # of the old convention of flattening control into inputs[0] plus a
        # transitional producer-side marker table. _all_nodes_topo's control-
        # aware walk (membership fixpoint + control_in-as-predecessor
        # ordering) guarantees a node's control predecessor is always
        # captured, and always emitted before it, whenever the node itself
        # is -- so the referenced index always resolves on load.
        if ($node->can('control_in') && defined $node->control_in
                && exists $id_remap{ $node->control_in->id }) {
            $entry{control_in} = $id_remap{ $node->control_in->id };
        }
        # Region.head -> the owning If/Loop, set at produce time (FromOptree's
        # StackSim::merge / _build_single_exit / Loop exit-Region sites; the
        # hand-written frontend's IfStatement/loop actions via set_region).
        # An If/Loop is always a control predecessor of the Region it owns,
        # so it is always already in the topo order (and hence in %id_remap)
        # by the time the Region itself is emitted -- no forward-ref defer-
        # patch needed (unlike the loop-Phi backedge).
        if ($node->operation eq 'Region' && defined $node->head
                && exists $id_remap{ $node->head->id }) {
            $entry{head} = $id_remap{ $node->head->id };
        }

        push @nodes, \%entry;
    }

    # Find start node positional ID
    my $start_pos = $id_remap{ $graph->start->id };

    # Find return node positional IDs
    my @return_pos = map { $id_remap{ $_->id } } $graph->returns->@*;

    return {
        nodes   => \@nodes,
        start   => $start_pos,
        returns => \@return_pos,
    };
}

# -----------------------------------------------------------------------
# to_json(\%named_graphs) — serialize named graphs to a JSON string.
# -----------------------------------------------------------------------
sub to_json ($named_graphs) {
    my %methods;
    for my $name (sort keys $named_graphs->%*) {
        $methods{$name} = _serialize_graph($named_graphs->{$name});
    }

    my $data = {
        version => 1,
        source  => undef,
        methods => \%methods,
    };

    return JSON::PP->new->canonical->pretty->encode($data);
}

# -----------------------------------------------------------------------
# _deserialize_graph($method_data) — rebuild a Chalk::IR::Graph from data.
# Handles the full SoN schema. Fields that Chalk nodes don't support
# (e.g., pattern/replacement on RegexMatch/RegexSubst, scope on VarDecl,
# stash_name/var_name on EntryDef) are silently dropped.
# -----------------------------------------------------------------------
sub _deserialize_graph ($method_data) {
    my $factory   = Chalk::IR::NodeFactory->new();
    my @node_data = $method_data->{nodes}->@*;

    my @nodes;  # positional array of created node objects
    my @backedge_patches;  # [phi_position, backedge_index] deferred wirings

    for my $nd (@node_data) {
        my $op     = $nd->{op};
        my $fields = $nd->{fields} // {};
        # Derived from the op name via %CFG_OPS -- the table that answers this
        # is defined 355 lines above (and to_json's emit side reads the same
        # table). The wire cfg:true key the emitter still writes is redundant
        # with $op and is ignored here.
        my $is_cfg = exists $CFG_OPS{$op};

        # Resolve inputs from already-created nodes. Nodes are built in array
        # order, so a valid input index is < the current node count; an index at
        # or beyond it is a FORWARD reference that resolves to undef here. The one
        # sanctioned forward edge is a loop Phi's backedge (inputs[1]), deferred
        # and patched below. Any OTHER forward index is a producer ordering bug
        # that would silently become an undef input and crash DEEP in the backend
        # (seen at LLVM.pm before the Graph::nodes DFS fix). Die at the seam,
        # naming the node/slot/index, so a future ordering bug is an immediate,
        # legible loader error rather than an opaque backend crash (zhi 019f26a5).
        my @input_idx = ($nd->{inputs} // [])->@*;
        my $phi_backedge_slot =
            ($op eq 'Phi' && @input_idx == 2 && $input_idx[1] >= @nodes) ? 1 : -1;
        for my $slot (0 .. $#input_idx) {
            my $idx = $input_idx[$slot];
            next if $slot == $phi_backedge_slot;   # sanctioned deferred backedge
            next if defined $idx && $idx >= 0 && $idx < @nodes;
            die "IR load: node #" . scalar(@nodes) . " ($op) input slot $slot "
              . "references index " . ($idx // 'undef') . ", which is not an "
              . "already-created node (have " . scalar(@nodes) . "); an "
              . "unresolvable forward input reference is a producer ordering bug.";
        }
        my @inputs = map { $nodes[$_] } @input_idx;

        # Build the argument hash, with inputs and any extra fields
        my %args = (inputs => \@inputs);

        # Merge extra fields based on op type.
        # For fields Chalk nodes don't support, we silently drop them.
        if ($op eq 'Constant') {
            $args{value}      = $fields->{value};
            $args{const_type} = $fields->{const_type} if exists $fields->{const_type};
        }
        elsif ($op eq 'Call') {
            $args{dispatch_kind} = $fields->{dispatch_kind};
            $args{name}          = $fields->{name};
            $args{param_names}   = $fields->{param_names}
                if exists $fields->{param_names};
            $args{class_name}    = $fields->{class_name}
                if exists $fields->{class_name};
            $args{paren_form}    = $fields->{paren_form}
                if exists $fields->{paren_form};
        }
        elsif ($op eq 'Phi') {
            $args{region} = $nodes[ $fields->{region} ];

            # predecessors[i] is the Proj that inputs[i] arrives along, carried
            # as node indices. It makes arm identity a field read instead of a
            # backward control-chain search -- see
            # docs/research/2026-08-18-phi-pairing-should-not-be-a-search.md.
            #
            # Optional on the wire (a loop Phi records none), and dropped
            # wholesale if any index fails to resolve: the consumer pairs by
            # POSITION, so a partial list would silently mis-pair, which is the
            # exact failure this field exists to remove.
            if (my $pred_ix = $fields->{predecessors}) {
                my @preds = map { $nodes[$_] } @$pred_ix;
                $args{predecessors} = \@preds
                    unless grep { !defined } @preds;
            }
            # A loop Phi's backedge input (inputs[1]) may reference a node
            # LATER in the array -- the Phi<->backedge data cycle forces one
            # forward edge in any serialization order, and a forward index
            # resolves to undef in the single pass above. Defer it: construct
            # the Phi with its init input only and wire inputs[1] via
            # set_backedge once every node exists (the same post-construction
            # patch the corpus builder uses for loop_backedge edges).
            my @idx = ($nd->{inputs} // [])->@*;
            if (@idx == 2 && $idx[1] >= @nodes) {
                push @backedge_patches, [ scalar @nodes, $idx[1] ];
                $args{inputs} = [ $inputs[0] ];
            }
        }
        elsif ($op eq 'Proj') {
            $args{index} = $fields->{index};
        }
        elsif ($op eq 'PadAccess') {
            $args{targ}    = $fields->{targ};
            $args{varname} = $fields->{varname};
        }
        elsif ($op eq 'Parameter') {
            # index is REQUIRED -- it is the node's identity. A missing one is a
            # producer/loader disagreement, not something to default away.
            $args{index} = $fields->{index};
            $args{name}  = $fields->{name};
            $args{sigil} = $fields->{sigil} // '$';
        }
        elsif ($op eq 'FieldAccess') {
            $args{field_index} = $fields->{field_index};
            $args{field_stash} = $fields->{field_stash};
        }
        elsif ($op eq 'CompoundAssign') {
            $args{op} = $fields->{op};
        }
        elsif ($op eq 'PostfixDeref') {
            $args{sigil} = $fields->{sigil};
        }
        elsif ($op eq 'EntryDef') {
            $args{stash_name} = $fields->{stash_name} // '';
            $args{var_name}   = $fields->{var_name}   // '';
            # REQUIRED, not defaulted. `_` alone names three different things
            # ($_, @_, and the `-f _` filetest handle), so a wire without a
            # sigil does not identify a variable -- defaulting one here would
            # invent an identity and re-merge what the producer kept apart.
            die "GAP: EntryDef '" . ($fields->{var_name} // '?')
              . "' arrived with no sigil -- the wire predates sigil-qualified "
              . "stash identity, or the producer failed to stamp it."
                unless defined $fields->{sigil};
            $args{sigil}      = $fields->{sigil};
        }
        elsif ($op eq 'RegexMatch') {
            $args{pattern} = $fields->{pattern} // '';
            $args{flags}   = $fields->{flags}   // '';
        }
        elsif ($op eq 'RegexSubst') {
            $args{pattern}     = $fields->{pattern}     // '';
            $args{replacement} = $fields->{replacement} // '';
            $args{flags}       = $fields->{flags}       // '';
        }
        elsif ($op eq 'RegexCapture') {
            $args{n} = $fields->{n};
        }
        elsif ($op eq 'EnvRead') {
            $args{key} = $fields->{key};
        }
        elsif ($op eq 'VarDecl') {
            $args{scope} = $fields->{scope} // 'my';
        }
        elsif ($op eq 'Coerce') {
            # from_repr/to_repr are REPRESENTATIONS named in the producer's stamp
            # vocabulary. The two vocabularies now agree name-for-name, so these
            # pass straight through; the reconciliation that used to happen here
            # existed only for Boolean, which chalk spelled 'Bool'.
            $args{from_repr} = $fields->{from_repr};
            $args{to_repr}   = $fields->{to_repr};
        }

        my $node;
        if ($is_cfg) {
            $node = $factory->make_cfg($op, %args);
        }
        else {
            $node = $factory->make($op, %args);
        }

        # Produce-time control: decode a genuine control_in wire key, emitted
        # by to_json for a graph built with control_in set directly (never
        # flattened into inputs[0]). Control-aware topo (_all_nodes_topo)
        # guarantees a node's control predecessor is always serialized
        # before it, so the referenced index is always already constructed
        # here.
        if (defined $nd->{control_in}) {
            $node->set_control_in($nodes[ $nd->{control_in} ]);
        }

        # Produce-time head/region: decode the genuine head wire key, emitted
        # by to_json for a Region whose owning If/Loop was set at produce
        # time (set_region installs both If.region and Region.head). The
        # owning If/Loop is always a control predecessor of the Region, so
        # control-aware topo guarantees it is already constructed here --
        # no defer-patch needed, unlike the loop-Phi backedge.
        if ($op eq 'Region' && defined $nd->{head}) {
            $nodes[ $nd->{head} ]->set_region($node);
        }

        # Map a B::SoN stamp to a Chalk representation so the backend can lower
        # the node runtime-free. Chalk's own serializer emits no stamp, so this
        # only fires for B::SoN-produced JSON.
        if (defined $nd->{stamp} && $LOWERABLE_STAMP{ $nd->{stamp} }) {
            $node->set_representation($nd->{stamp});
        }

        # A Print carries no stamp (the producer leaves it unstamped), but perl's
        # print returns a genuine boolean (builtin::is_bool true), so a
        # value-context `my $ok = print ...` reads Bool:1. Seed the repr as Boolean
        # so the return epilogue tags it correctly.
        if ($op eq 'Print') {
            $node->set_representation('Boolean');
        }

        push @nodes, $node;
    }

    # Wire the deferred loop-Phi backedges now that every node exists.
    for my $patch (@backedge_patches) {
        my ($phi_idx, $val_idx) = @$patch;
        $nodes[$phi_idx]->set_backedge($nodes[$val_idx]);
    }

    my $start   = $nodes[ $method_data->{start} ];
    my @returns = map { $nodes[$_] } $method_data->{returns}->@*;

    my $graph = Chalk::IR::Graph->new(start => $start, returns => \@returns);

    # A statement-effect node reachable ONLY through a Return's control_in chain
    # (a field store in an ADJUST body, whose result value is not the Return
    # value) is not seeded by start/returns and would be dropped from the graph's
    # membership. Merge each Return's control_in chain so those stores count as
    # body statements (the ADJUST emitter reads graph->members).
    for my $r (@returns) {
        my $c = $r->can('control_in') ? $r->control_in : undef;
        my %seen;
        while (defined $c && blessed($c) && !$seen{ $c->id }++) {
            $graph->merge($c);
            $c = $c->can('control_in') ? $c->control_in : undef;
        }
    }

    return $graph;
}

# -----------------------------------------------------------------------
# _resolve_direct_calls(\%graphs) — attach each direct sub call's callee graph.
# A Call with dispatch_kind='direct' names its callee (fully-qualified, e.g.
# main::foo); resolve that name against the loaded graph set and stash the graph
# so the Call's repr can be stamped from the callee's Return value. Calls
# whose name has no matching graph (builtins, unresolved) are left as-is.
# _all_graph_nodes($g) -> ($g->nodes PLUS control-chain nodes), deduped by id.
# $g->nodes walks inputs from the returns' value only, so a Call embedded in an
# if CONDITION (`if (($x = foo(1)) == 1)`) -- reached via control_in, not the
# Return value chain -- is absent. The call-stamping passes must see it to type
# the Call result (and thus the `$x = foo(1)` Assign consuming it).
sub _all_graph_nodes ($g) {
    my %seen;
    my @out;
    for my $n ($g->nodes->@*, _control_chain_nodes($g)) {
        next unless blessed($n);
        push @out, $n unless $seen{ $n->id }++;
    }
    return @out;
}

# _attach_call_targets(\%graphs, $mop) — give each resolved direct Call its
# callee METAOBJECT.
#
# The MOP is Chalk's deliberate divergence from classic Sea of Nodes: a flat
# graph dissolves declarations into itself, while Chalk keeps metaobjects
# alongside so a consumer can ASK rather than pattern-match. Every sub-level
# scan in this file exists because the B::SoN path skipped that layer.
#
# Keyed by the callee's fully-qualified name (`main::f`), which is how the
# producer names the graph and how declare_sub records the metaobject.
sub _attach_call_targets ($graphs, $mop) {
    for my $gname (sort keys $graphs->%*) {
        for my $node (_all_graph_nodes($graphs->{$gname})) {
            next unless $node->operation eq 'Call'
                && $node->can('dispatch_kind')
                && ($node->dispatch_kind // '') eq 'direct'
                && $node->can('set_target')
                && !defined $node->target;

            my ($cls_name, $sub_name) = ($node->name // '') =~ /^(.*)::([^:]+)$/;
            my $cls = defined $cls_name ? $mop->for_class($cls_name) : undef;
            my ($sub) = $cls
                ? (grep { $_->name eq $sub_name } $cls->subs)
                : ();

            if ($sub) {
                $node->set_target($sub);
                next;
            }

            # NO METAOBJECT. That is fine for a genuinely unresolvable callee (a
            # builtin, or a package outside the emission filter) -- those have no
            # graph either, and the backend's own GAP names them.
            #
            # But a callee with a resolved GRAPH and no metaobject is a
            # DISAGREEMENT between the two halves of the wire, and it is
            # reachable: the producer writes $graphs->{$full_name}
            # UNCONDITIONALLY and only then calls _record_sub, which returns
            # early for a `method` CV and for a `:reader` accessor. Measured --
            # `Widget::go($w)` on a class method gives rg=SET, target=UNDEF.
            #
            # The backend now resolves THROUGH the metaobject, so this would
            # surface there as "an unknown or builtin sub" -- actively wrong,
            # since the sub is neither. Say what is really true, here, where both
            # facts are in hand.
            # NO METAOBJECT. Quiet for a callee that is not the program's own
            # code -- a builtin, or an ambient module sub perl loaded along the
            # way (Carp::ret_summary and friends have a graph but deliberately
            # no sub record: B::SoN keys that on CV->FILE eq $0). Those simply
            # are not callable here, and the backend's own GAP says so.
            #
            # LOUD when the class IS in the MOP but the sub is not: that is a
            # genuine disagreement between the two halves of the wire, and it is
            # reachable -- the producer writes the graph unconditionally, then
            # _record_sub returns early for a `method` CV and for a `:reader`
            # accessor. Measured: `Widget::go($w)` on a class method gives a
            # graph with no metaobject. Resolving through the metaobject would
            # otherwise report "an unknown or builtin sub", which is wrong.
            die "GAP: direct call to '" . ($node->name // '?') . "' names class "
              . "'$cls_name', which IS in the MOP, but no sub '$sub_name' is "
              . "recorded on it. A `method` or `:reader` CV is emitted as a "
              . "graph but deliberately not recorded as a sub "
              . "(B::SoN::_record_sub's early returns), so it cannot be called "
              . "in sub form."
                if $cls && exists $graphs->{ $node->name // '' };
        }
    }
    return;
}

sub _resolve_direct_calls ($graphs) {
    for my $gname (sort keys $graphs->%*) {
        for my $node (_all_graph_nodes($graphs->{$gname})) {
            next unless $node->operation eq 'Call'
                && $node->can('dispatch_kind')
                && ($node->dispatch_kind // '') eq 'direct';
            my $callee = $graphs->{ $node->name } or next;

            # Stamp the Call's repr from the callee's Return value, so the
            # backend and the shape contract see the call result's type. The
            # callee's single Return input[-1] is its result value.
            unless (_is_narrowed($node->representation)) {
                my ($ret) = grep {
                    blessed($_) && $_->can('operation')
                        && $_->operation eq 'Return'
                } $callee->returns->@*;
                my $val = $ret ? $ret->inputs->[-1] : undef;
                $node->set_representation($val->representation)
                    if $val && _is_narrowed($val->representation);
            }
        }
    }
    return;
}

# -----------------------------------------------------------------------
# _seed_direct_call_arg_reprs(\%graphs) -> count of nodes newly stamped.
#
# A callee compiled in isolation reads its Nth positional argument via a
# `shift @_` (Call(builtin,shift) over ArgsSource), which has no type on
# its own -- so an expression over it (`shift + 1`) stays untyped and the
# backend's NO-REPR guard would fire. The type is known at the CALL site: it is
# the argument's repr. Stamp the callee's single `shift @_` read with the
# resolved call's argument repr so the universal propagation carries the type
# into the callee body (and then to the Call result via _resolve_direct_calls'
# return-value stamp). Only the sound single-`shift`, single-argument shape is
# seeded (the backend inlines exactly that shape; other @_ shapes GAP there).
# Run inside the repr fixpoint: a callee-of-a-callee is typed once its own
# callee's shift is stamped on a prior pass.
sub _seed_direct_call_arg_reprs ($graphs) {
    my $stamped = 0;
    for my $gname (sort keys $graphs->%*) {
        for my $node (_all_graph_nodes($graphs->{$gname})) {
            next unless $node->operation eq 'Call'
                && $node->can('dispatch_kind')
                && ($node->dispatch_kind // '') eq 'direct'
                && $node->can('target') && $node->target;
            my @args = grep { blessed($_) } $node->inputs->@*;
            next unless @args;

            # Find the callee's single positional argument read: either a
            # `shift @_` (Call builtin shift over ArgsSource) or a `$_[0]`
            # subscript (Subscript over Constant("_") at index 0). Both bind the
            # first argument; stamp whichever the callee uses.
            my $callee = $node->target->graph;

            # A DECLARED SIGNATURE stamps by INDEX, and is not capped at one
            # argument the way the `shift @_` / `$_[0]` recovery paths below
            # are. Those cap at one because multiple shifts hash-cons to a
            # single node and lose their order; a Parameter carries its index,
            # so parameter N pairs with argument N by construction.
            my %params;
            for my $n ($callee->nodes->@*) {
                next unless blessed($n) && $n->operation eq 'Parameter';
                $params{ $n->index } = $n;
            }
            if (%params) {
                for my $i ( sort { $a <=> $b } keys %params ) {
                    # A parameter with no matching argument is an arity
                    # mismatch; leave it untyped and let the backend GAP
                    # against the operation that needed a type, rather than
                    # guessing here.
                    my $arg = $args[$i] or next;
                    my $repr = $arg->representation // next;
                    # Same monomorphic-callee assumption as the shift path
                    # below: first caller wins, and a second caller with a
                    # different repr lowers through the first one's ops, which
                    # lli rejects loudly rather than miscompiling silently.
                    next if _is_narrowed($params{$i}->representation);
                    $params{$i}->set_representation($repr);
                    $stamped++;
                }
                next;
            }

            my @reads = grep {
                my $n = $_;
                blessed($n) && $n->operation eq 'Call'
                    && $n->can('dispatch_kind')
                    && ($n->dispatch_kind // '') eq 'builtin'
                    && defined $n->name && $n->name eq 'shift'
                    && do {
                        my ($op) = grep { blessed($_) } $n->inputs->@*;
                        $op && $op->operation eq 'ArgsSource';
                    };
            } $callee->nodes->@*;
            unless (@reads) {
                # `$_[0]`: Subscript(ArgsSource, Constant(0), Mem).
                #
                # The container used to be a string Constant("_") -- the array
                # spelled as its own NAME -- so this had to match a literal.
                # With @_ as a node kind the container is simply that node.
                @reads = grep {
                    my $n = $_;
                    blessed($n) && $n->operation eq 'Subscript' && do {
                        my ($c, $i) = grep { blessed($_) } $n->inputs->@*;
                        $c && $c->operation eq 'ArgsSource'
                            && $i && $i->operation eq 'Constant' && $i->can('value')
                            && defined $i->value && $i->value eq '0';
                    };
                } $callee->nodes->@*;
            }
            next unless @reads == 1 && @args == 1;

            my $arg_repr = $args[0]->representation // next;
            # ponytail: monomorphic callee assumption — the callee's arg read is
            # stamped by the FIRST caller's arg repr and shared across call
            # sites. A second caller with a DIFFERENT repr (Str vs Int) does not
            # re-stamp; the backend then lowers its arg through the first repr's
            # ops, which lli rejects as a type mismatch (a loud verify error, not
            # a silent miscompile). Per-callsite specialization if polymorphic
            # direct calls ever need to lower.
            next if _is_narrowed($reads[0]->representation);
            $reads[0]->set_representation($arg_repr);
            $stamped++;
        }
    }
    return $stamped;
}

# from_json($json_string) — deserialize JSON to named Chalk::IR::Graph instances.
# -----------------------------------------------------------------------
sub from_json ($json_string) {
    my $data    = JSON::PP->new->decode($json_string);
    my %graphs;
    for my $name (sort keys $data->{methods}->%*) {
        $graphs{$name} = _deserialize_graph($data->{methods}{$name});
    }

    # ANALYSIS RUNS IN ITS OWN MODULE. These passes are not deserialization --
    # every one takes graphs (plus class metadata) and none touches the JSON --
    # so they live in Chalk::IR::Analysis and the phase boundary is explicit.
    # See docs/plans/2026-08-24-loader-analysis-pipeline.md, slice 1.
    #
    # from_json keeps this call so its ~40 existing callers are unchanged. A
    # caller that wants a DECODED-BUT-UNANALYSED graph set should call
    # _deserialize_graph directly; there is deliberately no flag here, because a
    # half-analysed graph is not a thing any current consumer wants.
    # `require` at the call site, not `use` at the top: the two modules refer to
    # each other (Analysis calls the pass subs that still live here), and a
    # compile-time `use` on both sides is a load cycle. A runtime require breaks
    # it. Note a `perl -c` of this file passes WITHOUT the require -- the
    # missing load only surfaces when from_json is actually called, which is why
    # this is a require rather than a comment saying "remember to load it".
    require Chalk::IR::Analysis;
    my ($analysed, $mop) = Chalk::IR::Analysis->run(
        \%graphs, (ref $data->{classes} eq "HASH" ? $data->{classes} : undef));

    # $mop is returned only in list context; scalar context stays \%graphs for
    # the existing single-return callers.
    return ($analysed, $mop) if wantarray && defined $mop;
    return $analysed;
}

# _insert_str_coercions(\%graphs) — wrap a non-Str operand of a Str-context
# operator in a Coerce(X -> Str).
#
# Print(Str...) and StrEq/StrNe(Str, Str) take Str; a non-Str operand is bridged
# by a coercion rather than the operator learning a representation. The producer
# does this at its build site, but only for an operand that carries a STAMP
# there. A call's return type is not known until the loader resolves the callee
# (`say($c->get)`), so the producer sees an unstamped operand and correctly
# declines to guess — leaving it to arrive here typed.
#
# Runs after every repr fixpoint, the first point the operand's representation
# is known. Idempotent: an operand already produced by a Coerce is skipped, so a
# graph loaded twice does not stack coercions.
# Nodes whose OWN contract fixes an operand repr, independent of any source
# signature. `Print(Str...)` is the standing example: the IR node lowers ONE
# representation and every argument position is Str, while the source builtin
# `print` is variadic over `List` because perl flattens a LIST into it. Those are
# two different claims about two different things -- see the `print @a` case in
# t/corpus/mdtest/statements.md -- so the node contract is stated HERE, on the
# node, and is not sought in TypeLibrary's builtin table.
#
# Everything else asks the signature. This hash exists for genuine node-level
# contracts only; an entry that merely restates a source signature belongs in
# TypeLibrary instead.
my %_NODE_OPERAND_REPR = (Print => 'Str');

# The scalar representations a value can be CONVERTED to, keyed by source repr.
# Mirrors the arms _lower_coerce implements (Context.pm) -- this pass must not
# mint a Coerce the backend cannot lower, which would turn a clear type error
# into a confusing "not lowered runtime-free" GAP one layer too late.
#
# Aggregates (Array/Hash/ArrayRef/HashRef/CodeRef) are deliberately ABSENT: no
# conversion from an aggregate to a scalar repr is defined, so an aggregate in a
# scalar position is a type error to REPORT, not a coercion to invent. Slot is
# absent as a SOURCE for the same reason it is present as a target elsewhere --
# it is a backend cell, unwrapped at its use site rather than converted here.
my %_COERCIBLE_TO = (
    Int   => { Num => 1, Str => 1, Boolean => 1 },
    Num   => { Int => 1, Str => 1, Boolean => 1 },
    Str   => { Num => 1, Boolean => 1 },
    Boolean  => { Int => 1, Num => 1, Str => 1 },
    Undef => { Int => 1, Num => 1, Str => 1, Boolean => 1 },
    Slot  => { Str => 1 },
);

# _coercion_exists($from, $to) -> bool. Is this conversion defined at all?
sub _coercion_exists ($from, $to) {
    return false if !defined $from || !defined $to;
    return ($_COERCIBLE_TO{$from} && $_COERCIBLE_TO{$from}{$to}) ? true : false;
}

# _required_operand_repr($op, $position) -> repr, or undef for "no opinion".
#
# The node's own contract first, then the source signature. A position with no
# answer is left alone: a missed coercion GAPs loudly downstream, whereas a
# guessed one is a silent wrong answer.
sub _required_operand_repr ($op, $position) {
    return $_NODE_OPERAND_REPR{$op}
        if exists $_NODE_OPERAND_REPR{$op};
    return Chalk::Grammar::Perl::TypeLibrary::operand_repr_for_ir_op($op, $position);
}

sub _insert_str_coercions ($graphs) {
    my $inserted = 0;
    # Its own factory: _deserialize_graph's is per-graph and not retained, and a
    # node's identity is its content hash, so nodes minted here are consistent
    # with the ones already in the graph.
    my $factory = Chalk::IR::NodeFactory->new();
    for my $name (sort keys %$graphs) {
        my $g = $graphs->{$name} or next;
        for my $node (_all_graph_nodes($g)) {
            next unless $node->can('operation');
            my $op = $node->operation;
            my $inputs = $node->inputs // next;
            for my $i (0 .. $inputs->$#*) {
                # Asked PER POSITION, because signatures are per position --
                # `substr(Str, Num, Num)` wants different types at different
                # operands, which a whole-node flag cannot express.
                my $want = _required_operand_repr($op, $i) // next;

                my $in = $inputs->[$i];
                next unless defined $in && ref $in && ref($in) ne 'ARRAY';
                next unless $in->can('representation');
                my $repr = $in->representation;
                # undef repr: nothing established a type, so a coercion here
                # would be the guess the producer already declined to make.
                # The backend reports it against the operator, which names the
                # node that actually needs a type.
                next unless defined $repr;
                next if $repr eq $want;
                next if $in->isa('Chalk::IR::Node::Coerce');

                # A position that accepts a SET takes this repr as-is.
                next if Chalk::Grammar::Perl::TypeLibrary::accepts_operand_repr($op, $repr);

                # A COERCION IS A CONVERSION, NOT A SUBSUMPTION. Whether one
                # exists is a question about the PAIR -- is this conversion
                # defined? -- and NOT a question about the lattice. Int->Str is
                # legitimate because stringification is defined for an Int, not
                # because Int <: Str; Boolean->Str is equally legitimate even
                # though Boolean is a SIBLING of Str under Scalar and no subtype
                # relation holds in either direction.
                #
                # Keying this on subtyping was wrong twice over, both measured:
                # requiring `is_subtype($repr, $want)` un-lowered six cases
                # whose Boolean/Slot operands print perfectly well, and exempting
                # Str wholesale then un-lowered eight more by stringifying the
                # ArrayRef operand of `scalar @a`.
                #
                # The defined pairs are the ones _lower_coerce implements
                # (Context.pm _lower_coerce): Int<->Num, anything->Boolean,
                # Boolean->Num/Int, Undef->Int/Num, scalars->Str, Str->Num/Boolean.
                # Aggregates appear in NONE of them -- an ArrayRef reaching a
                # scalar position is a type error to report, not a missing
                # conversion to invent.
                next unless _coercion_exists($repr, $want);

                my $c = $factory->make('Coerce',
                    inputs    => [$in],
                    from_repr => $repr,
                    to_repr   => $want,
                );
                $c->set_representation($want);
                $inputs->[$i] = $c;
                $inserted++;
            }
        }
    }
    return $inserted;
}

# _narrow_unknown_coercions(\%graphs) -> count of Coerce nodes narrowed.
#
# A Coerce carrying from_repr 'Unknown' is a coercion whose SOURCE type was not
# determined when the node was built. 'Unknown' is the pessimistic top type
# (TypeScript's `unknown`, not its `any`): it holds any value but obliges the
# holder to NARROW it before use. This is that narrowing.
#
# The producer writes it for an unstamped operand, which is honest at its stage
# -- a direct call's result cannot be typed while the callee's graph may not
# exist yet. By the time this runs every repr fixpoint has completed and the
# operand usually carries a concrete repr, so the Coerce is REBUILT against it.
#
# Rebuilt, not mutated: from_repr is part of Coerce's content_hash (per
# typed-ir-representation.md, Coerce[Str->Num](x) and Coerce[Int->Num](x) are
# distinct nodes), so narrowing changes the node's IDENTITY. Mutating in place
# would leave a node whose hash no longer matches its contents, which breaks
# hash-consing. The consumer's input slot is repointed and the old Coerce is
# removed from its operand's consumer list, so no orphan is left listed as a
# reader of a node it no longer reads.
#
# An Unknown that CANNOT be narrowed is left alone deliberately: the backend
# then reports it as an inference failure naming the operand, which is the
# whole point of distinguishing Unknown from Scalar. A Scalar GAP means "this
# scalar type is not lowered"; an Unknown GAP means "nothing ever typed this".
sub _narrow_unknown_coercions ($graphs) {
    my $narrowed = 0;
    my $factory  = Chalk::IR::NodeFactory->new();

    for my $name (sort keys %$graphs) {
        my $g = $graphs->{$name} or next;
        for my $node (_all_graph_nodes($g)) {
            my $inputs = ($node->can('inputs') ? $node->inputs : undef) or next;

            for my $i (0 .. $inputs->$#*) {
                my $c = $inputs->[$i];
                next unless blessed($c)
                         && $c->isa('Chalk::IR::Node::Coerce')
                         && ($c->from_repr // '') eq 'Unknown';

                my $operand = ($c->inputs // [])->[0];
                next unless blessed($operand) && $operand->can('representation');
                my $repr = $operand->representation;

                # Still untyped: leave the Unknown in place so the backend can
                # report it. Narrowing to a guess here would recreate exactly
                # the bug this replaced.
                next unless _is_narrowed($repr);

                # The operand is ALREADY the target type: the coercion is an
                # identity edge and the consumer can read the operand directly.
                if ($repr eq $c->to_repr) {
                    $inputs->[$i] = $operand;
                    $c->remove_consumer($node) if $c->can('remove_consumer');
                    $operand->remove_consumer($c) if $operand->can('remove_consumer');
                    $narrowed++;
                    next;
                }

                my $new = $factory->make('Coerce',
                    inputs    => [$operand],
                    from_repr => $repr,
                    to_repr   => $c->to_repr,
                );
                $new->set_representation($c->to_repr);

                $inputs->[$i] = $new;
                # The old Coerce no longer reads the operand.
                $operand->remove_consumer($c) if $operand->can('remove_consumer');
                $narrowed++;
            }
        }
    }
    return $narrowed;
}

# _ctor_arg_reprs(\%graphs) -> ("class\0param_name" => repr, ...)
# Scan every graph for Call(new) nodes; each binds param_names[i] to inputs[i],
# so it records the repr of the argument passed for each named :param. First
# first construction wins (//=). Two safety constraints the review flagged:
#   (1) DETERMINISM: iterate graphs in a stable (sorted-key) order, so a class
#       constructed more than once with divergent arg reprs resolves the same
#       way every run (the determinism constraint).
#   (2) SAFE REPRS ONLY: infer a field type only for reprs the :param-binding +
#       field-read path actually lowers (Int, Str — proven by field-basic/A5).
#       A Num-looking literal (3.0) whose value is integer would mis-type the
#       field Num and lower into malformed IR (i64 value into a double slot);
#       the constant-DEFAULT path GAPs loudly on Num, so the inference must not
#       be LESS safe. Anything but Int/Str stays uninferred (an honest GAP,
#       exactly as before this inference existed).
my %_INFERABLE_FIELD_REPR = (Int => 1, Str => 1);

sub _ctor_arg_reprs ($graphs) {
    my %map;
    for my $key (sort keys %$graphs) {
        my $g = $graphs->{$key};
        for my $node ($g->nodes->@*) {
            next unless $node->operation eq 'Call'
                && ($node->name // '') eq 'new'
                && $node->can('param_names');
            my $class = $node->class_name // next;
            my $pn    = $node->param_names // next;
            my @args  = $node->inputs->@*;
            for my $i (0 .. $#$pn) {
                my $arg  = $args[$i] or next;
                my $repr = blessed($arg) ? $arg->representation : undef;
                next unless defined $repr && $_INFERABLE_FIELD_REPR{$repr};
                $map{"$class\0" . $pn->[$i]} //= $repr;
            }
        }
    }
    return %map;
}

# _replay_classes($classes, \%graphs) — rebuild a sealed Chalk::MOP from the
# declarative class section, wiring each method to its loaded graph. Parents are
# declared before children so `superclass =>` can reference the parent's class.
sub _replay_classes ($classes, $graphs) {
    require Chalk::MOP;

    # Field types are inferred onto the raw records before this point (ctor-arg
    # and ADJUST-store passes in from_json), so declare_field below sees them.

    my $mop = Chalk::MOP->new;

    for my $name (_classes_in_parent_order($classes)) {
        my $cd     = $classes->{$name};
        my $parent = $cd->{parent};
        my $super  = (defined $parent && length $parent)
            ? $mop->for_class($parent)
            : undef;

        my $cls = $mop->declare_class($name,
            (defined $super  ? (superclass  => $super)  : ()),
            (defined $parent ? (parent_name => $parent) : ()),
        );

        for my $f (($cd->{fields} // [])->@*) {
            my $vname = $f->{name} // '$?';
            my @attrs;
            push @attrs, ':param'  if $f->{is_param};
            push @attrs, ':reader' if $f->{is_reader};

            # A field default (4c-1b) rides as a graph-ref whose Return value is
            # the default Constant; wire it as default_value + has_default. The
            # field type (inferred from the default) becomes the field repr.
            my ($default_node, $has_default);
            if (defined $f->{default_ref}
                && (my $dg = $graphs->{ $f->{default_ref} })) {
                my ($dret) = $dg->returns->@*;
                $default_node = $dret ? $dret->inputs->[0] : undef;
                $has_default  = defined $default_node;
            }

            # A field whose default is an aggregate literal (`field $items = []`
            # / `[1,2,3]` / `{}`) is an ArrayRef/HashRef, regardless of what the
            # producer inferred for its `type` (which reads the first element's
            # scalar type -- e.g. "integer" for `[10,20,30]`, a wrong scalar
            # type). The default node is already repr-seeded ArrayRef/HashRef by
            # %_SEED_REPR, and that repr is unambiguous (unlike the ctor-arg /
            # ADJUST-store scalar inference, which the %_INFERABLE_FIELD_REPR gate
            # guards), so lift it to the field type. This is what makes a
            # FieldAccess to the field (and its :reader Call) carry ArrayRef so a
            # `$items->[0]` / `scalar $items->@*` / `for my $x ($items->@*)`
            # lowers (zhi 019f61ad).
            my $field_type = $f->{type};
            if (defined $default_node && $default_node->can('representation')
                    && ($default_node->representation // '') =~ /^(?:Array|Hash)Ref$/) {
                $field_type = $default_node->representation;
            }

            $cls->declare_field($vname,
                sigil      => substr($vname, 0, 1),
                param_name => $f->{param_name},
                attributes => \@attrs,
                (defined $field_type ? (type => $field_type) : ()),
                ($has_default
                    ? (default_value => $default_node, has_default => true)
                    : ()),
            );
        }

        my $methods = $cd->{methods} // {};
        for my $mname (sort keys %$methods) {
            my $graph = $graphs->{ $methods->{$mname} };
            $cls->declare_method($mname,
                (defined $graph ? (graph => $graph) : ()),
            );
        }

        # Subs (1b): a `sub` is not a `method` -- it carries no implicit
        # invocant -- so it replays into a MOP::Sub rather than a MOP::Method.
        # The wire distinguishes them at the producer (CvFLAGS & CVf_METHOD).
        #
        # This is the metadata channel that lets consumers STOP recovering
        # sub-level facts by scanning the graph: uses_args in particular cannot
        # be derived reliably, since `@_` has three IR spellings and vanishes
        # entirely for `my ($a,$b) = @_`.
        my $subs = $cd->{subs} // {};
        for my $sname (sort keys %$subs) {
            my $sd  = $subs->{$sname};
            my $key = $sd->{graph} // '';
            # REFUSE a record whose graph is missing rather than declaring a
            # graph-less MOP::Sub. MOP::Sub's `graph` field defaults to a fresh
            # EMPTY Chalk::IR::Graph, not undef, so a consumer's `defined`
            # check cannot tell "no body" from "a body" -- it would inline
            # nothing and silently produce a wrong answer. The producer records
            # a sub only after its translate() succeeds, so a missing graph
            # means the wire and the graph set disagree; say so loudly.
            my $graph = $graphs->{$key}
                or die "GAP: class '$name' declares sub '$sname' with graph key "
                     . "'$key', which is not in the loaded graph set.";
            # The producer DECLARES the return type; the loader CARRIES it. A
            # wire without the field predates the declaration and arrives as
            # `Unknown` -- the lattice top -- never as undef. `Unknown` is a
            # real type meaning "inference has not determined this"; undef is
            # an ABSENCE, and an absence forces every downstream consumer to
            # invent its own meaning for it.
            $cls->declare_sub($sname,
                graph       => $graph,
                params      => ($sd->{params} // []),
                uses_args   => ($sd->{uses_args} ? true : false),
                return_type => ($sd->{return_type} // 'Unknown'),
            );
        }

        # ADJUST blocks (4c-1b): each rides as a graph-ref; replay via
        # declare_adjust with the loaded graph.
        for my $aref (($cd->{adjusts} // [])->@*) {
            my $ag = $graphs->{$aref} or next;
            $cls->declare_adjust(graph => $ag);
        }
    }

    $mop->seal;

    # FieldAccess reprs are stamped by from_json's pre-seal pass (before
    # _replay_classes is called), and _mop->seal / class replay does not create
    # new FieldAccess nodes or re-type fields, so a tail re-stamp here is
    # redundant (idempotent) -- removed in the 019f4625 cleanup pass. The
    # universal repr pass (_seed_and_propagate_reprs) and method-Call stamping
    # run afterward in from_json as before.

    return $mop;
}

# _propagate_computed_reprs(\%graphs) — fixpoint-propagate representations onto
# computed nodes whose inputs are now typed (e.g. a FieldAccess stamped from its
# field type feeds an Add). Mirrors the producer's result-stamp rules so a field
# read flowing into arithmetic carries a repr to the method body root.
my %_COMPUTED_REPR = (
    # A Phi (control-flow value merge) and a TernaryExpr carry the JOIN of their
    # arm reprs -- a merge of two Ints is Int, an Int|Str widens to Str -- the
    # same rule _make_ternary uses. An early-return merged into single-exit
    # (`return X if C`, `E // return X`) reaches the backend as a Region+Phi over
    # the exit values, which the backend cannot lower without an explicit repr.
    # DefinedOr (`$a // $b`) is the same kind of merge: it yields ONE of its two
    # operands, so its repr is their join, exactly as a TernaryExpr's is. It was
    # missing here, so `$a // $b` reached the backend with no representation --
    # invisible while its only consumer was the return epilogue (which reads the
    # repr from elsewhere), and surfacing the moment a Str context needed to
    # coerce it: "Print of a representation-less arg".
    Phi => 'join', TernaryExpr => 'join', DefinedOr => 'join',
    # And (&&) / Or (||) RETURN ONE OF THEIR OPERANDS (`$a && $b` is $a or $b, not
    # a fresh boolean), so the result repr is the JOIN of the operands -- the same
    # rule Phi and TernaryExpr use, because all three are merges of operands.
    #
    # This was 'same' (require the two reprs to agree, yield that repr) because
    # the backend's merge phi is ONE instruction needing ONE machine type, and a
    # mismatched pair could not be lowered at all. It can now: the backend
    # bridges a non-conforming ARM with a coercion to the node's repr, so the
    # join is what tells it WHICH type to bridge to. Measured, 'join' is a strict
    # superset of 'same' here -- it types Boolean&&Boolean -> Boolean and Int&&Int -> Int
    # exactly as before, and additionally types Int&&Str -> Str and
    # Int&&Num -> Num, which 'same' left untyped.
    #
    # Boolean mixed with a chain member (Int&&Boolean, Boolean&&Str) still joins to undef
    # -- Boolean is a sibling of the Int <: Num <: Str chain under Scalar, not a
    # point on it -- and stays a loud GAP, as it did under 'same'.
    And => 'join', Or => 'join',
    Add => 'join', Subtract => 'join', Multiply => 'join', Negate => 'join',
    Divide => 'Num', Power => 'Num', Modulo => 'Int',
    BitAnd => 'Int', BitOr => 'Int', BitXor => 'Int',
    LeftShift => 'Int', RightShift => 'Int', Complement => 'Int',
    Concat => 'Str', Length => 'Int',
    # ref($x) reads the type/class name of a reference -- always a Str,
    # regardless of the operand (ref($obj) -> class name, ref([...]) -> "ARRAY").
    RefType => 'Str',
    # Predicates are always Boolean. Defined/Not gate an early-return guard
    # (`E // return X` lowers to If(Not(Defined(E)))); the backend needs an
    # explicit Boolean repr on the If condition to emit an i1 branch.
    (map { $_ => 'Boolean' } qw(
        NumEq NumLt NumGt NumLe NumGe NumNe StrEq StrLt StrGt StrLe StrGe StrNe
        Defined Not)),
    NumCmp => 'Int', StrCmp => 'Int',
);
# _join_repr(@reprs) -> the widest, or undef when they do not share a chain.
#
# Derived from the TYPE LATTICE rather than a hand-kept widening order. This was
# `%_REPR_RANK = (Int => 0, Num => 1, Str => 2)`, which is exactly the lattice's
# Int <: Num <: Str chain re-encoded as integers -- a second copy of something
# TypeLibrary already states, and the same duplication the Add requirement had.
#
# The lattice also EXPLAINS the two exclusions the rank table could only record
# as absence: Undef and Boolean are siblings under Scalar, not points on the
# numeric-to-string chain, so neither widens into it. Verified against
# is_subtype: Int <: Num <: Str all hold; Undef <: Str, Undef <: Num,
# Boolean <: Str and Boolean <: Num all do not.
#
# Returns undef when no candidate is a supertype of every repr -- the caller
# leaves the node untyped and the backend GAPs loudly, rather than guessing a
# widened type the merge phi cannot express.
sub _join_repr (@reprs) {
    return undef unless @reprs;

    # `Unknown` is the SOUND TOP, so it is a supertype of everything and wins
    # every join -- discarding the arm that inference DID determine. But it is
    # not a claim about the value at all; it is an admission that inference has
    # not finished, so it contributes no constraint and must not narrow the
    # result. Drop it and join the rest.
    #
    # Guarded like the `Undef` drop below (:1548): if EVERY arm is Unknown
    # there is nothing known, and the join must stay Unknown rather than empty
    # the list and return a vacuous answer. The two drops differ in kind --
    # `Undef` is dropped for a SEMANTIC reason, `Unknown` for an EPISTEMIC one.
    my @known = grep { $_ ne 'Unknown' } @reprs;
    @reprs = @known if @known;

    for my $cand (@reprs) {
        return $cand
            if !grep { !Chalk::Grammar::Perl::TypeLibrary::is_subtype($_, $cand) }
                     @reprs;
    }
    return undef;
}

# Aggregate/regex nodes whose OWN repr is fixed by their kind (RC1). An
# ArrayRef/HashRef literal is a boxed aggregate pointer; a RegexMatch result is
# a boolean.
my %_SEED_REPR = (
    ArrayRef   => 'ArrayRef',
    HashRef    => 'HashRef',
    RegexMatch => 'Boolean',
);

# _seed_and_propagate_reprs(\%graphs) — the universal repr pass (runs for EVERY
# graph, class or not). Seeds aggregate/regex node reprs, then fixpoint-
# propagates through computed nodes and aggregate reads (Subscript) until no
# more reprs can be derived.
sub _seed_and_propagate_reprs ($graphs) {
    for my $g (values %$graphs) {
        # Seed over $g->nodes PLUS the control-chain closure. A loop CONDITION
        # (a comparison with control_in=Loop) and its input closure -- e.g. the
        # `Length(@a)` bound of a foreach-over-array (`for my $x (@a)`) and the
        # array ArrayRef -- are reachable only via the Loop's consumers, not the
        # Return value chain, so $g->nodes alone omits them. Without a seed the
        # ArrayRef/Length never get a repr and hit the backend NO-REPR guard when
        # the loop-condition is lowered (only visible when the body does not also
        # read an element, which would pull the array into the value chain).
        my %seen;
        my @seed_nodes;
        for my $n ($g->nodes->@*, _control_chain_nodes($g)) {
            next unless blessed($n);
            push @seed_nodes, $n unless $seen{ $n->id }++;
        }
        for my $node (@seed_nodes) {
            next if _is_narrowed($node->representation);
            # A qr// compiled-regex literal is a Constant of const_type 'regex';
            # its repr is Regex (the matcher value the backend resolves
            # statically). Keyed on const_type, not node kind, so it can't live
            # in the op-keyed seed table.
            if ($node->operation eq 'Constant'
                && $node->can('const_type')
                && ($node->const_type // '') eq 'regex') {
                $node->set_representation('Regex');
                next;
            }
            my $seed = $_SEED_REPR{ $node->operation } // next;
            $node->set_representation($seed);
        }
    }
    _propagate_computed_reprs($graphs);
    return;
}

# _control_chain_nodes($graph) — the statement-effect nodes reachable ONLY via
# control_in (an element-store Assign / void Call demoted to control_in), PLUS
# their transitive input closure. $g->nodes walks inputs from the returns' value
# only, so a store's value subtree (e.g. `$a[0] = $b[0]`, where $b[0] is reached
# only through the store) is otherwise unseen and stays untyped. Follows
# control_in from every returns() node, then closes over inputs of each.
#
# A loop-body / branch-body store whose RESULT is never read (no value edge and
# no post-body read observes its memory) is reachable only through the body's
# control node (a Proj). The Return's control_in chain reaches the Loop/If via
# the exit Region's inputs, but the BODY Proj hangs off the Loop/If as a
# consumer, and the store hangs off that body Proj as a consumer. So this walk
# also follows consumers that are Projs (the CFG body entry) or statement effects
# (nodes carrying a control_in — the stores themselves). The consumer step is
# scoped to those two kinds — arbitrary value fan-out is not pulled in — so it
# discovers control-only-reachable stores without over-collecting (019f3559).
sub _control_chain_nodes ($graph) {
    my %seen;
    my @out;
    # Seed: the control_in predecessor of each return + effect in the chain,
    # PLUS any trailing void statement-effect Calls carried as extra Return
    # inputs. A void method call (`$c->inc;`) is not the return value, so the
    # loader keeps it as inputs[1..] rather than demoting it to control_in; its
    # own control_in chain threads the preceding void effects. Seeding from it
    # here lets those effects be discovered and repr-stamped (else the backend
    # NO-REPR guard fires on a non-tail void Call).
    my @q;
    for my $r (grep { blessed($_) } $graph->returns->@*) {
        my $c = $r->can('control_in') ? $r->control_in : undef;
        push @q, $c if defined $c && blessed($c);
        if ($r->can('inputs') && defined $r->inputs) {
            my @ins = $r->inputs->@*;
            push @q, grep {
                blessed($_) && $_->can('control_in') && defined $_->control_in
            } @ins[ 1 .. $#ins ];
        }
    }
    while (my $n = shift @q) {
        next unless blessed($n);
        next if $seen{ $n->id }++;
        push @out, $n;
        # Follow control_in (chained effects) AND inputs (the effect's operands).
        my $c = $n->can('control_in') ? $n->control_in : undef;
        push @q, $c if defined $c && blessed($c);
        push @q, grep { blessed($_) } $n->inputs->@*
            if $n->can('inputs') && defined $n->inputs;
        # Follow consumers that are body Projs (the CFG entry into a loop/branch
        # body) or statement effects (nodes carrying a control_in — the stores
        # themselves): a body-nested store hangs off its body Proj as a consumer,
        # and that Proj hangs off the Loop/If as a consumer, so consumers are the
        # only edges that reach it.
        if ($n->can('consumers') && defined $n->consumers) {
            push @q, grep {
                blessed($_)
                    && ($_->operation eq 'Proj'
                        || ($_->can('control_in') && defined $_->control_in))
            } $n->consumers->@*;
        }
    }
    return @out;
}

sub _propagate_computed_reprs ($graphs) {
    for my $g (values %$graphs) {
        # $g->nodes walks inputs only; a threaded statement-effect node (an
        # element-store Assign / void Call) reached only via control_in is not in
        # it. Augment with the control-chain nodes so their reprs get inferred
        # too -- else a store of a value whose repr this pass derives (e.g. a
        # Subscript) leaves the Assign untyped and it hits the backend NO-REPR
        # guard.
        my %seen;
        my @nodes;
        for my $n ($g->nodes->@*, _control_chain_nodes($g)) {
            next unless blessed($n);
            push @nodes, $n unless $seen{ $n->id }++;
        }
        my $changed = 1;
        while ($changed) {
            $changed = 0;
            for my $node (@nodes) {
                next if _is_narrowed($node->representation);
                my $op = $node->operation;

                # A Subscript reads an element out of an aggregate container:
                # its repr is the element type, inferred from the container's
                # element reprs (an ArrayRef/HashRef of Ints yields an Int).
                # BUT a statically-provable MISS (an out-of-bounds literal array
                # index, or a hash key absent from a literal HashRef) reads
                # perl's undef, not an element -- it must load as Slot (the
                # tagged {defined=false} path the backend prints as Undef:), NOT
                # the element type (which the backend prints as the payload 0, a
                # silent miscompile). Only fires over a SCALAR-literal aggregate
                # (a Constant index/key and a container whose inputs are all
                # plain scalars -- no nested list-flattening aggregate); a
                # dynamic index/key or a flattened container stays the element
                # repr (019f2e25).
                if ($op eq 'Subscript') {
                    if (_static_miss( $node->inputs->[0], $node->inputs->[1] )) {
                        $node->set_representation('Slot');
                        $changed = 1;
                        next;
                    }
                    my $repr = _element_repr( $node->inputs->[0] );
                    next unless defined $repr;
                    $node->set_representation($repr);
                    $changed = 1;
                    next;
                }

                # An Assign's result IS the stored value, so its repr is the
                # value input's (inputs[-1], the rhs; a stmt-effect store's
                # leading control was already split off by the loader). Run in
                # the fixpoint so the value's own repr (e.g. a Subscript inferred
                # this same pass) is available before the Assign is stamped.
                if ($op eq 'Assign') {
                    my $value = $node->inputs->[-1];
                    next unless defined $value && blessed($value);
                    my $repr = $value->representation // next;
                    $node->set_representation($repr);
                    $changed = 1;
                    next;
                }

                my $rule = $_COMPUTED_REPR{$op} // next;
                if ($rule ne 'join' && $rule ne 'same') {
                    $node->set_representation($rule);
                    $changed = 1;
                    next;
                }
                my @in = grep { defined && blessed($_) } $node->inputs->@*;

                # A TernaryExpr's inputs are (cond, then, else), but `$c ? $a :
                # $b` NEVER evaluates to `$c` -- the condition is not a value
                # the expression can yield, so it must not enter the join.
                # Including it poisons the result: a Boolean condition is off the
                # Int<:Num<:Str chain, so no candidate dominates and the node
                # goes untyped even when both arms agree.
                #
                # The PRODUCER already joins arms-only (FromOptree.pm:4145,
                # Stamp::join($true_val->stamp, $false_val->stamp)); this side
                # disagreed with it. Order is documented there: inputs[1]=true,
                # inputs[2]=false.
                #
                # TernaryExpr ONLY. Phi's inputs are its arms, and DefinedOr is
                # a BinOp whose two operands are both results -- neither has a
                # condition among its inputs to drop.
                @in = @in[ 1 .. $#in ] if $op eq 'TernaryExpr' && @in > 1;

                my @reprs = map { $_->representation } @in;
                next if grep { !defined } @reprs;          # an input still untyped
                if ($rule eq 'same') {
                    # And/Or: the result IS one operand, so both must share a repr.
                    # Leave untyped (the backend GAPs loudly) on a genuine mismatch
                    # rather than guess a widened type the merge phi can't express.
                    my %uniq = map { $_ => 1 } @reprs;
                    next unless keys %uniq == 1;
                    $node->set_representation($reprs[0]);
                    $changed = 1;
                    next;
                }
                # Undef is not RANKED -- it is not wider or narrower than Int,
                # it is a different thing -- but it is not unknown either. A
                # merge of Undef with T yields T on the arm that is taken, and
                # the Undef arm contributes no value to widen: `my $a; $a // 9`
                # is 9, and a ternary whose other arm is Undef yields the
                # defined arm's type.
                #
                # Dropping the Undef arms BEFORE ranking is what lets that
                # merge type at all; without it the grep below bails on the
                # unranked Undef and the merge reaches the backend untyped --
                # which reads as a defective merge when the real defect is that
                # the lattice has no rule for the absence case.
                my @ranked = grep { $_ ne 'Undef' } @reprs;
                @reprs = @ranked if @ranked;

                my $widest = _join_repr(@reprs);
                next unless defined $widest;
                $node->set_representation($widest);
                $changed = 1;
            }
        }
    }
    return;
}

# _unwrap_ref($container) — a Ref container (`$r->[0]` where $r=\@a) aliases its
# target aggregate, so element-repr / static-miss inference must read the wrapped
# ArrayRef/HashRef, not the Ref (which carries no aggregate structure of its own).
# No-op for every non-Ref container. Mirrors Target::LLVM::_unwrap_ref_container.
sub _unwrap_ref ($container) {
    return $container unless defined $container && blessed($container)
        && $container->operation eq 'Ref';
    return $container->inputs->[0];
}

# _resolve_aggregate($node) — follow a chain of Subscript reads over LITERAL
# aggregates at CONSTANT indices back to the concrete aggregate node being read,
# so a nested deref ($r->[1][0]) can be typed statically. `Subscript(ArrayRef
# literal, const idx)` resolves to the ArrayRef's idx-th input; a HashRef needs a
# literal-key scan (not modelled -- returns the node unchanged, an honest fall
# through to undef). Returns the node unchanged when it is not a resolvable
# Subscript. Cycle-guarded via a bounded depth (aggregate nesting is shallow).
sub _resolve_aggregate ($node) {
    my $depth = 0;
    while (blessed($node) && $node->operation eq 'Subscript' && $depth++ < 64) {
        my $c   = _unwrap_ref($node->inputs->[0]);
        my $idx = $node->inputs->[1];
        last unless blessed($c) && $c->operation eq 'ArrayRef'
            && blessed($idx) && $idx->operation eq 'Constant'
            && ($idx->const_type // '') eq 'integer';
        my $i   = $idx->value;
        my @els = $c->inputs->@*;
        # Only a provable in-bounds literal index resolves; anything else stays a
        # Subscript (falls through to undef -- an honest GAP, not a guess).
        last if $i < 0 || $i > $#els;
        $node = _unwrap_ref($els[$i]);
    }
    return $node;
}

# _element_repr($container) — the element type of an ArrayRef/HashRef container,
# inferred as the widest element repr of its inputs. For a HashRef the inputs
# alternate key,value; the values are the odd positions. Returns undef when the
# element types are not yet known.
sub _element_repr ($container) {
    $container = _resolve_aggregate(_unwrap_ref($container));
    return undef unless defined $container && blessed($container);
    my $op = $container->operation;
    my @in = $container->inputs->@*;
    my @elems;
    if ($op eq 'ArrayRef') {
        @elems = @in;
    }
    elsif ($op eq 'HashRef') {
        @elems = @in[ grep { $_ % 2 } 0 .. $#in ];   # odd = values
    }
    else {
        return undef;   # container repr not a literal aggregate we can read
    }
    my @reprs = map { blessed($_) ? $_->representation : undef } @elems;
    return undef unless @reprs;
    return undef if grep { !defined } @reprs;
    # A NESTED aggregate: the elements are themselves aggregates ([[1,2],[3,4]]).
    # Aggregate reprs (ArrayRef/HashRef) are not scalar-widenable, so the element
    # type is that repr only when every element shares it homogeneously; a mixed
    # aggregate/scalar or ArrayRef/HashRef element set has no single element type
    # (references R8). Scalar elements fall through to the widening below.
    my %uniq = map { $_ => 1 } @reprs;
    if (keys %uniq == 1 && ($reprs[0] eq 'ArrayRef' || $reprs[0] eq 'HashRef')) {
        return $reprs[0];
    }
    return _join_repr(@reprs);
}

# _static_miss($container, $index) — true iff a Subscript read is a provable
# MISS at load time: an out-of-bounds integer index into a literal ArrayRef, or
# a string key absent from a literal HashRef. Only literal-over-literal accesses
# are decidable here; a dynamic container or index returns false (the read keeps
# the element repr and is bounds-checked at runtime). A miss reads perl's undef,
# so the Subscript must load as Slot, not the element type.
sub _static_miss ($container, $index) {
    # Resolve a nested container the SAME way _element_repr does: a Subscript over
    # a literal aggregate at a constant index resolves to the inner literal, so an
    # OOB inner index ($r->[1][5]) is a provable miss. This MUST mirror
    # _element_repr's resolution -- if the two disagree, an OOB nested read gets
    # the element type (Int) instead of a Slot and silently reads 0 instead of
    # undef (a miscompile; found by the R8 nested-deref adversarial review).
    $container = _resolve_aggregate(_unwrap_ref($container));
    return false unless defined $container && blessed($container);
    return false unless defined $index && blessed($index)
        && $index->operation eq 'Constant';
    my $op = $container->operation;

    # A nested aggregate input is Perl list-flattening ((@x, 99) / (%base, ...)):
    # it occupies ONE input slot but expands to many elements at runtime, so a
    # static length or key-scan over inputs is wrong. Bail to element-repr (a
    # HIT) -- deciding a miss here would turn a valid read into a false Slot
    # (undef). Only a scalar-literal aggregate (all inputs plain scalars) is
    # statically decidable.
    my $flattens = grep {
        blessed($_) && ($_->operation eq 'ArrayRef' || $_->operation eq 'HashRef')
    } $container->inputs->@*;
    return false if $flattens;

    if ($op eq 'ArrayRef') {
        # An integer literal index; out of bounds (or negative past the start)
        # is a miss. A negative index within range (perl's from-the-end) is NOT
        # a miss, so only flag idx >= len or idx < -len.
        return false unless ($index->const_type // '') eq 'integer';
        my $idx = $index->value;
        my $len = scalar $container->inputs->@*;
        return ($idx >= $len || $idx < -$len) ? true : false;
    }
    if ($op eq 'HashRef') {
        # A string key absent from the literal keys (even positions) is a miss.
        my $key = $index->value // return false;
        my @in  = $container->inputs->@*;
        for my $i (grep { $_ % 2 == 0 } 0 .. $#in) {   # even = keys
            my $k = $in[$i];
            next unless blessed($k) && $k->operation eq 'Constant';
            return false if ($k->value // '') eq $key;   # present -> not a miss
        }
        return true;   # exhausted the literal keys with no match
    }
    return false;   # container not a literal aggregate we can decide
}

# _infer_param_field_types($classes, \%graphs) — type a :param field with no
# declared type from the CONSTRUCTOR ARGUMENT: a Call(new) binds param_names[i]
# -> inputs[i], so a field whose param_name matches carries the argument's repr.
# Fills the raw field record so declare_field (the MOP / struct layout) and
# _stamp_field_access_reprs (the FieldAccess nodes) both see it. Cross-graph: the
# Call(new) is in the driver graph, the field in a class section. Returns the
# number of field types newly inferred.
sub _infer_param_field_types ($classes, $graphs) {
    my %ctor_arg_repr = _ctor_arg_reprs($graphs);
    my $inferred = 0;
    for my $cname (keys %$classes) {
        for my $f (($classes->{$cname}{fields} // [])->@*) {
            next if defined $f->{type};
            my $pn = $f->{param_name} // next;
            my $repr = $ctor_arg_repr{"$cname\0$pn"} // next;
            $f->{type} = $repr;
            $inferred++;
        }
    }
    return $inferred;
}

# _infer_field_types_from_stores($classes, \%graphs) — type a field with no
# declared type from the value an ADJUST block stores into it. An ADJUST store
# is Assign(control, FieldAccess(ix)-lvalue, value); when the value carries a
# repr, that repr is the field's type. Writes the type onto the raw field record
# (so _stamp_field_access_reprs and the MOP both see it) only when the field is
# still untyped — never overrides a declared or constructor-argument type.
# Returns the number of field types newly inferred.
sub _infer_field_types_from_stores ($classes, $graphs) {
    # (class, fieldix) -> stored value repr, from Assign(FieldAccess-lvalue, val).
    # A stmt-effect field store is threaded via control_in (not a data input of
    # the Return), so it is reachable only by following control_in as well as
    # data inputs -- Graph::nodes walks data edges, so collect the store nodes by
    # a BFS over both edge kinds from each Return.
    my %store_repr;
    for my $g (values %$graphs) {
        my %seen;
        my @queue = grep { blessed($_) } $g->returns->@*;
        while (my $node = shift @queue) {
            next if $seen{ $node->id }++;
            push @queue, grep { blessed($_) } $node->inputs->@*;
            push @queue, $node->control_in
                if $node->can('control_in') && blessed($node->control_in);

            next unless $node->operation eq 'Assign';
            # A loaded stmt-effect Assign carries control in control_in, so its
            # data inputs are [target, value].
            my ($lv, $val) = ($node->inputs->[0], $node->inputs->[1]);
            next unless blessed($lv) && $lv->operation eq 'FieldAccess';
            next unless blessed($val);
            my $repr = $val->representation // next;
            my $key  = ($lv->field_stash // '') . "\0" . ($lv->field_index // -1);
            # A field written with conflicting reprs across stores is ambiguous;
            # leave it untyped (a GAP) rather than pick one (a possible miscompile).
            $store_repr{$key} = exists $store_repr{$key}
                && ($store_repr{$key} // '') ne $repr ? undef : $repr;
        }
    }

    my $inferred = 0;
    for my $cname (keys %$classes) {
        for my $f (($classes->{$cname}{fields} // [])->@*) {
            next if defined $f->{type};
            my $repr = $store_repr{"$cname\0" . ($f->{fieldix} // -1)} // next;
            $f->{type} = $repr;
            $inferred++;
        }
    }
    return $inferred;
}

# _stamp_field_access_reprs($classes, \%graphs) — set each FieldAccess node's
# representation from its declared field type. The field type comes from the
# class section (4c-1b infers it from the field default); the backend needs a
# repr on the FieldAccess to lower a field read.
sub _stamp_field_access_reprs ($classes, $graphs) {
    # Build (class, fieldix) -> type from the class sections. For an aggregate
    # (ArrayRef/HashRef) field, also record its ELEMENT type from the default's
    # elements -- an `field $items = [10,20,30]` field reads Int elements. A
    # Subscript over a FieldAccess to that field (`$items->[0]`, `$items->@*` in
    # a loop) then carries the element repr (zhi 019f61ad).
    my (%field_type, %field_elem_type, %reader_graph_type);
    for my $cname (keys %$classes) {
        for my $f (($classes->{$cname}{fields} // [])->@*) {
            my $key = "$cname\::" . ($f->{fieldix} // -1);
            $field_type{$key} = $f->{type} if defined $f->{type};

            # A :reader field gets a SYNTHESIZED accessor graph, named
            # Class::fieldname, whose body reads the field through a PadAccess
            # rather than the FieldAccess an explicit `method get { return $v }`
            # produces. Same field, same type, different node kind -- and the
            # FieldAccess arm below is the only rule that ever typed it, so the
            # accessor body reached the end of the pipeline untyped.
            #
            # Record (graph name, varname) -> type so the walk can type it. The
            # varname is matched too: an accessor graph contains exactly one
            # field read, but keying on the graph alone would type ANY PadAccess
            # that appeared there, and a future accessor body with a local would
            # be silently mistyped.
            if ($f->{is_reader} && defined $f->{type} && defined $f->{name}) {
                my $accessor = $f->{name} =~ s/^[\$\@\%]//r;
                $reader_graph_type{"$cname\::$accessor"} =
                    { varname => $f->{name}, type => $f->{type} };
            }
            # An aggregate default's element repr (widest of its elements).
            if (defined $f->{default_ref}
                    && (my $dg = $graphs->{ $f->{default_ref} })) {
                my ($dret) = $dg->returns->@*;
                my $default = $dret ? $dret->inputs->[0] : undef;
                if (defined $default && blessed($default)
                        && $default->operation =~ /^(?:Array|Hash)Ref$/) {
                    my $er = _element_repr($default);
                    $field_elem_type{$key} = $er if defined $er;
                }
            }
        }
    }

    for my $gname (keys %$graphs) {
        my $g = $graphs->{$gname};
        my $reader = $reader_graph_type{$gname};
        for my $node ($g->nodes->@*) {
            # The :reader accessor's field read (see %reader_graph_type above).
            if ($reader && $node->operation eq 'PadAccess'
                    && !_is_narrowed($node->representation)
                    && $node->can('varname')
                    && ($node->varname // '') eq $reader->{varname}) {
                $node->set_representation($reader->{type});
                next;
            }
            if ($node->operation eq 'FieldAccess' && !_is_narrowed($node->representation)) {
                my $stash = $node->field_stash // next;
                my $fidx  = $node->field_index;
                my $type  = $field_type{"$stash\::" . ($fidx // -1)} // next;
                $node->set_representation($type);
                next;
            }
            # A Subscript reading an element out of an aggregate FIELD: its repr
            # is the field's element type (the container is a FieldAccess, not a
            # literal aggregate _element_repr can read). A LITERAL constant index
            # is left for the OOB->Slot path (references R9); only a non-literal
            # index needs this (its own _element_repr sees a FieldAccess).
            if ($node->operation eq 'Subscript' && !_is_narrowed($node->representation)) {
                my $cont = $node->inputs->[0];
                next unless blessed($cont) && $cont->operation eq 'FieldAccess';
                my $er = $field_elem_type{
                    ($cont->field_stash // '') . '::' . ($cont->field_index // -1) };
                next unless defined $er;
                $node->set_representation($er);
            }
        }
    }
    return;
}

# _stamp_method_call_reprs($classes, \%graphs) — set each method Call's repr
# from the resolved callee method's return repr (its body's Return value repr).
sub _stamp_method_call_reprs ($classes, $graphs) {
    # Build class::method -> return_repr.
    #
    # THE WIRE IS THE FIRST SOURCE, not the graph walk. The producer computes
    # each method's return type where it built the Return and knows the value
    # node, and ships it in the `method_return_types` sibling map (a sibling
    # because the {methods} value must stay a bare graph-name string that both
    # repos index the graph map with). Re-deriving what was already sent is the
    # recovery-by-scanning that the metadata channel exists to retire.
    #
    # The graph walk REMAINS, for two reasons: the producer sends `Unknown`
    # where it genuinely cannot tell (it works method-by-method and cannot see
    # a caller), and this loader has the whole program, so it can often do
    # better. Measured on plain subs: 11 of 15 agreed, 4 were Unknown-on-wire
    # and derivable here, ZERO disagreed.
    #
    # WHERE BOTH COMMIT AND DISAGREE, THAT IS A DEFECT IN ONE OF THEM. Nothing
    # compared them before, so a divergence would have been silent -- the
    # backend consuming one answer while the metadata channel carried another.
    # Refuse loudly instead.
    my %ret_repr;
    for my $cname (keys %$classes) {
        my $methods  = $classes->{$cname}{methods} // {};
        my $wire_rts = $classes->{$cname}{method_return_types} // {};

        for my $mname (keys %$methods) {
            my $wire = $wire_rts->{$mname};
            $ret_repr{"$cname\::$mname"} = $wire
                if _is_narrowed($wire);

            my $g = $graphs->{ $methods->{$mname} } or next;
            my ($ret) = $g->returns->@*;
            next unless $ret;
            my $val = $ret->inputs->[0];
            next unless defined $val && blessed($val);
            my $repr = $val->representation;
            # Not merely `defined`: an unnarrowed graph-derived repr is not a
            # second opinion, so it must not be compared against the wire's.
            # `Unknown ne Str` is true and would fire the disagreement die
            # below on a graph that simply has nothing to say yet.
            next unless _is_narrowed($repr);

            if (_is_narrowed($wire) && $wire ne $repr) {
                die "IR: method $cname\::$mname has return type '$wire' on the "
                  . "wire but '$repr' derived from its graph. One of the two is "
                  . "wrong; refusing rather than picking silently.\n";
            }
            $ret_repr{"$cname\::$mname"} = $repr;
        }

        # A :reader field has no method graph — the backend synthesizes the
        # accessor. Its return repr IS the field type (filled by _replay_classes
        # from the default or the constructor argument). The reader method is
        # named after the field, sigil-stripped.
        for my $f (($classes->{$cname}{fields} // [])->@*) {
            next unless $f->{is_reader} && defined $f->{type};
            my $rname = ($f->{name} // '') =~ s/^[\$\@%]//r;
            $ret_repr{"$cname\::$rname"} = $f->{type} if length $rname;
        }
    }

    # Walk every graph's method Calls and stamp from the resolved callee.
    # Augment $g->nodes (input closure only) with the control-chain nodes: a
    # void method Call (`$c->inc;`) reached only via control_in is otherwise
    # unseen here and hits the backend NO-REPR guard.
    my $stamped = 0;
    for my $g (values %$graphs) {
        my %seen;
        my @nodes = grep { !$seen{ $_->id }++ }
            ($g->nodes->@*, _control_chain_nodes($g));
        for my $node (@nodes) {
            next unless $node->operation eq 'Call';
            next unless ($node->dispatch_kind // '') eq 'method';
            next if ($node->name // '') eq 'new';   # constructor: backend-handled
            next if _is_narrowed($node->representation);
            my $class = $node->class_name // next;
            my $mname = $node->name // '';
            # Resolve the method through the class's MRO: a call on Child of a
            # method inherited from Base has no Child::m entry, so walk the
            # parent chain until the method is found (or the chain ends).
            my $repr;
            my $c = $class;
            my %seen;
            while (defined $c && !$seen{$c}++) {
                if (defined(my $r = $ret_repr{"$c\::$mname"})) { $repr = $r; last; }
                $c = $classes->{$c}{parent};
            }
            defined $repr or next;
            $node->set_representation($repr);
            $stamped++;
        }
    }
    return $stamped;
}

# _classes_in_parent_order($classes) — class names sorted so a parent always
# precedes its children (a child's superclass must already be declared).
sub _classes_in_parent_order ($classes) {
    my @order;
    my %placed;
    my $place;
    $place = sub ($name) {
        return if $placed{$name};
        my $parent = $classes->{$name}{parent};
        $place->($parent) if defined $parent && exists $classes->{$parent};
        $placed{$name} = 1;
        push @order, $name;
    };
    $place->($_) for sort keys %$classes;
    return @order;
}

1;
