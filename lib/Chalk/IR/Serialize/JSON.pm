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

# CFG node operations — these carry control tokens and are never hash-consed.
my %CFG_OPS = map { $_ => 1 } qw(Start Return Unwind If Proj Region Loop);

# Map a B::SoN stamp lattice type to a Chalk representation. B::SoN carries type
# info as a `stamp` (SoN::IR::Stamp lattice: Int < Num < Str < Scalar, plus
# Boolean/Undef/refs); Chalk's backend requires an explicit `representation`.
# Only the concrete, lowerable types map; anything else is left unset (the
# backend's _require_repr then reports an honest GAP rather than mislowering).
my %STAMP_TO_REPR = (
    Int     => 'Int',
    Num     => 'Num',
    Str     => 'Str',
    Boolean => 'Bool',
    Undef   => 'Undef',
    Object  => 'Object',
);

# -----------------------------------------------------------------------
# _is_cfg($node) — true if the node is a CFG node
# -----------------------------------------------------------------------
sub _is_cfg ($node) {
    return exists $CFG_OPS{ $node->operation };
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
    if ($op eq 'StashAccess') {
        return {
            stash_name => $node->stash_name,
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
        $entry{cfg}    = JSON::PP::true if _is_cfg($node);
        $entry{fields} = $fields        if defined $fields;
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
# stash_name/var_name on StashAccess) are silently dropped.
# -----------------------------------------------------------------------
sub _deserialize_graph ($method_data) {
    my $factory   = Chalk::IR::NodeFactory->new();
    my @node_data = $method_data->{nodes}->@*;

    my @nodes;  # positional array of created node objects
    my @backedge_patches;  # [phi_position, backedge_index] deferred wirings

    for my $nd (@node_data) {
        my $op     = $nd->{op};
        my $fields = $nd->{fields} // {};
        my $is_cfg = $nd->{cfg}    // 0;

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
        elsif ($op eq 'StashAccess') {
            $args{stash_name} = $fields->{stash_name} // '';
            $args{var_name}   = $fields->{var_name}   // '';
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

        # Map a B::SoN stamp to a Chalk representation so the backend can lower
        # the node runtime-free. Chalk's own serializer emits no stamp, so this
        # only fires for B::SoN-produced JSON.
        if (defined $nd->{stamp} && exists $STAMP_TO_REPR{ $nd->{stamp} }) {
            $node->set_representation($STAMP_TO_REPR{ $nd->{stamp} });
        }

        # A Print carries no stamp (the producer leaves it unstamped), but perl's
        # print returns a genuine boolean (builtin::is_bool true), so a
        # value-context `my $ok = print ...` reads Bool:1. Seed the repr as Bool
        # so the return epilogue tags it correctly.
        if ($op eq 'Print') {
            $node->set_representation('Bool');
        }

        push @nodes, $node;
    }

    # Wire the deferred loop-Phi backedges now that every node exists.
    for my $patch (@backedge_patches) {
        my ($phi_idx, $val_idx) = @$patch;
        $nodes[$phi_idx]->set_backedge($nodes[$val_idx]);
    }

    # Wire each Region's head back-pointer to the If/Loop that owns it. B::SoN's
    # JSON does not carry it, but the backend's control-chain walk needs
    # $region->head to reach the enclosing If/Loop (and emit its Phis). A Region
    # merges arms; each arm's control is a Proj of the owning If/Loop -- either
    # DIRECTLY (an empty arm's control IS the Proj, the 2b-1 if-only shape) or
    # via the arm's control_in chain (an arm that STORED advanced its control to
    # the store node, whose control_in is the Proj -- the 2b-3 if/else both-arms-
    # store shape). Follow control_in from the first arm until a Proj is found.
    for my $node (@nodes) {
        next unless $node->operation eq 'Region';
        next if $node->head;
        # Scan EVERY input for the owning Proj, not just the first. An early-
        # return merge normalized to single-exit (`return X if C`, `E // return
        # X`) builds Region inputs = [pre-branch-control, exit-Proj] -- the Proj
        # is at index 1, and inputs[0] (the pre-branch control, often Start) has
        # no control_in chain to a Proj. Checking only inputs[0] left head unset,
        # so the backend pushed the bare Region and never wired the If's Phi
        # (Phi-before-Region die). Follow each arm's control_in until a Proj.
        my $owner;
        for my $start ($node->inputs->@*) {
            my $arm = $start;
            my %seen;
            while (defined $arm && blessed($arm)
                    && $arm->operation ne 'Proj' && !$seen{$arm->id}++) {
                $arm = $arm->can('control_in') ? $arm->control_in : undef;
            }
            next unless defined $arm && blessed($arm)
                && $arm->operation eq 'Proj';
            my $cand = $arm->inputs->[0];
            if (defined $cand && blessed($cand)) { $owner = $cand; last }
        }
        next unless defined $owner;
        # set_region installs BOTH directions: If.region -> this Region (the
        # forward pointer the backend's _process_if_node reads to wire the merge
        # Phis) AND Region.head -> the If (the back-pointer the control-chain
        # walk follows). Setting only head left If.region unset, so the backend
        # skipped Phi wiring. Fall back to set_head for an owner without
        # set_region (defensive; If/Loop both have it).
        if ($owner->can('set_region')) { $owner->set_region($node) }
        else                           { $node->set_head($owner) }
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
# on the Call via set_resolved_graph so the backend can lower the call. Calls
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

sub _resolve_direct_calls ($graphs) {
    for my $gname (sort keys $graphs->%*) {
        for my $node (_all_graph_nodes($graphs->{$gname})) {
            next unless $node->operation eq 'Call'
                && $node->can('dispatch_kind')
                && ($node->dispatch_kind // '') eq 'direct';
            my $callee = $graphs->{ $node->name } or next;
            $node->set_resolved_graph($callee);

            # Stamp the Call's repr from the callee's Return value, so the
            # backend and the shape contract see the call result's type. The
            # callee's single Return input[-1] is its result value.
            unless (defined $node->representation) {
                my ($ret) = grep {
                    blessed($_) && $_->can('operation')
                        && $_->operation eq 'Return'
                } $callee->returns->@*;
                my $val = $ret ? $ret->inputs->[-1] : undef;
                $node->set_representation($val->representation)
                    if $val && defined $val->representation;
            }
        }
    }
    return;
}

# -----------------------------------------------------------------------
# _seed_direct_call_arg_reprs(\%graphs) -> count of nodes newly stamped.
#
# A callee compiled in isolation reads its Nth positional argument via a
# `shift @_` (Call(builtin,shift) over StashAccess(*,_)), which has no type on
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
                && $node->can('resolved_graph') && $node->resolved_graph;
            my @args = grep { blessed($_) } $node->inputs->@*;
            next unless @args;

            # Find the callee's single positional argument read: either a
            # `shift @_` (Call builtin shift over StashAccess(_)) or a `$_[0]`
            # subscript (Subscript over Constant("_") at index 0). Both bind the
            # first argument; stamp whichever the callee uses.
            my $callee = $node->resolved_graph;
            my @reads = grep {
                my $n = $_;
                blessed($n) && $n->operation eq 'Call'
                    && $n->can('dispatch_kind')
                    && ($n->dispatch_kind // '') eq 'builtin'
                    && defined $n->name && $n->name eq 'shift'
                    && do {
                        my ($op) = grep { blessed($_) } $n->inputs->@*;
                        $op && $op->operation eq 'StashAccess'
                            && $op->can('var_name') && ($op->var_name // '') eq '_';
                    };
            } $callee->nodes->@*;
            unless (@reads) {
                # `$_[0]`: Subscript(Constant("_"), Constant(0), Mem).
                @reads = grep {
                    my $n = $_;
                    blessed($n) && $n->operation eq 'Subscript' && do {
                        my ($c, $i) = grep { blessed($_) } $n->inputs->@*;
                        $c && $c->operation eq 'Constant' && $c->can('value')
                            && ($c->value // '') eq '_'
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
            next if defined $reads[0]->representation;
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

    # Resolve each direct sub call (dispatch_kind='direct') to its callee graph
    # by name, so the backend can lower the call to the callee's result. A
    # top-level named sub is its own graph (keyed by fully-qualified name), not a
    # MOP class method; the Call carries the graph on resolved_graph.
    _resolve_direct_calls(\%graphs);

    # 4c: a `classes` section (from B::SoN) is replayed into a sealed MOP. Field
    # types must be inferred onto the raw records BEFORE the MOP is sealed, so
    # each declared field carries its type (the backend reads it from the MOP).
    my $mop;
    if (ref $data->{classes} eq 'HASH' && %{ $data->{classes} }) {
        my $classes = $data->{classes};

        # A :param field's type comes from the constructor argument.
        _infer_param_field_types($classes, \%graphs);
        # Stamp the field reads that are already typed, then propagate so an
        # ADJUST expression over them (`$val * 2`) carries a repr.
        _stamp_field_access_reprs($classes, \%graphs);
        _seed_and_propagate_reprs(\%graphs);
        # An ADJUST-only field (no :param, no default) is typed from the value an
        # ADJUST stores into it (Assign(FieldAccess-lvalue, value)). Re-stamp the
        # now-typed field reads (the accessor body's FieldAccess) after.
        if (_infer_field_types_from_stores($classes, \%graphs)) {
            _stamp_field_access_reprs($classes, \%graphs);
        }

        $mop = _replay_classes($classes, \%graphs);
    }

    # Universal repr-inference: seed aggregate/regex reprs and fixpoint-propagate
    # through computed + aggregate-read nodes for EVERY graph (class or not).
    # The backend requires a repr on these nodes to lower them (RC1).
    _seed_and_propagate_reprs(\%graphs);

    # Stamp method Calls from the callee's return_repr, then re-propagate: a Call
    # newly types nodes a computed expression consumes (Add over a method-Call
    # result), which the next propagation resolves. This is a FIXPOINT: a method
    # whose BODY consumes a call (`method use_it { $self->a() + 1 }`) has no
    # return_repr until its internal call is stamped AND its body root re-derived,
    # so a caller of use_it can only be stamped on a LATER pass. Loop stamp +
    # propagate until a pass stamps nothing new (zhi 019f5e57). Bounded by the
    # finite number of Call nodes; a graph with no method Calls converges in one
    # pass (stamped==0 immediately).
    while (_stamp_method_call_reprs($data->{classes} // {}, \%graphs) > 0) {
        _seed_and_propagate_reprs(\%graphs);
    }

    # Direct-call argument binding (F5): a callee's `shift @_` arg-read is typed
    # from the caller's argument repr, then the callee body (and the Call result)
    # re-derive. Fixpoint: a callee reached through a chain is typed once the
    # outer call's arg is known on a prior pass. After seeding, the Call's own
    # result repr is picked up from the callee Return via _resolve_direct_calls'
    # stamp logic, which we re-run to catch calls newly resolvable this pass.
    while (_seed_direct_call_arg_reprs(\%graphs) > 0) {
        _seed_and_propagate_reprs(\%graphs);
        _resolve_direct_calls(\%graphs);
    }
    # The loop stamps a Call's result repr in _resolve_direct_calls AFTER the
    # pass's _seed_and_propagate_reprs already ran, so a consumer of the call
    # result (an `$x = foo(5)` Assign) is still untyped when the loop exits. Run
    # one final propagation so the now-stamped Calls flow into their consumers.
    _seed_and_propagate_reprs(\%graphs);

    # $mop is returned only in list context; scalar context stays \%graphs for
    # the existing single-return callers.
    return (\%graphs, $mop) if wantarray && defined $mop;
    return \%graphs;
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
    Phi => 'join', TernaryExpr => 'join',
    # And (&&) / Or (||) RETURN ONE OF THEIR OPERANDS (`$a && $b` is $a or $b, not a
    # fresh boolean), so the result repr is the operands' -- and both operands must
    # share a machine type for the backend's merge phi. The 'same' rule requires the
    # two operand reprs to agree and yields that repr. This types Bool && Bool -> Bool
    # (a comparison guard && a print, the cond.t idiom) as well as Int && Int -> Int
    # -- unlike 'join', which cannot widen Bool (it has no _REPR_RANK).
    And => 'same', Or => 'same',
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
    # explicit Bool repr on the If condition to emit an i1 branch.
    (map { $_ => 'Bool' } qw(
        NumEq NumLt NumGt NumLe NumGe NumNe StrEq StrLt StrGt StrLe StrGe StrNe
        Defined Not)),
    NumCmp => 'Int', StrCmp => 'Int',
);
# Widening order for the 'join' rule (Int < Num < Str).
my %_REPR_RANK = (Int => 0, Num => 1, Str => 2);

# Aggregate/regex nodes whose OWN repr is fixed by their kind (RC1). An
# ArrayRef/HashRef literal is a boxed aggregate pointer; a RegexMatch result is
# a boolean.
my %_SEED_REPR = (
    ArrayRef   => 'ArrayRef',
    HashRef    => 'HashRef',
    RegexMatch => 'Bool',
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
            next if defined $node->representation;
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
                next if defined $node->representation;
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
                next if grep { !exists $_REPR_RANK{$_} } @reprs;
                my ($widest) = sort { $_REPR_RANK{$b} <=> $_REPR_RANK{$a} } @reprs;
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
    return undef if grep { !exists $_REPR_RANK{$_} } @reprs;
    my ($widest) = sort { $_REPR_RANK{$b} <=> $_REPR_RANK{$a} } @reprs;
    return $widest;
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
    my (%field_type, %field_elem_type);
    for my $cname (keys %$classes) {
        for my $f (($classes->{$cname}{fields} // [])->@*) {
            my $key = "$cname\::" . ($f->{fieldix} // -1);
            $field_type{$key} = $f->{type} if defined $f->{type};
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

    for my $g (values %$graphs) {
        for my $node ($g->nodes->@*) {
            if ($node->operation eq 'FieldAccess' && !defined $node->representation) {
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
            if ($node->operation eq 'Subscript' && !defined $node->representation) {
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
    # Build class::method -> return_repr from the loaded method graphs.
    my %ret_repr;
    for my $cname (keys %$classes) {
        my $methods = $classes->{$cname}{methods} // {};
        for my $mname (keys %$methods) {
            my $g = $graphs->{ $methods->{$mname} } or next;
            my ($ret) = $g->returns->@*;
            next unless $ret;
            my $val = $ret->inputs->[0];
            next unless defined $val && blessed($val);
            my $repr = $val->representation;
            $ret_repr{"$cname\::$mname"} = $repr if defined $repr;
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
            next if defined $node->representation;
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
