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
    return undef;
}

# -----------------------------------------------------------------------
# _all_nodes_topo($graph) — return all nodes in topological order.
# Graph->nodes() does a DFS over inputs[] only; Phi nodes reference a
# region via a separate field (not inputs[]), so Region may appear after
# Phi in Graph->nodes() output. This function re-sorts to ensure
# Phi region references are always serialized before their Phi nodes.
# -----------------------------------------------------------------------
sub _all_nodes_topo ($graph) {
    my $base = $graph->nodes;

    # Collect any Phi region nodes not already in the base list.
    my %seen = map { $_->id => 1 } $base->@*;
    my @extra;
    for my $node ($base->@*) {
        if ($node->operation eq 'Phi') {
            my $region = $node->region;
            next unless defined $region;
            next if $seen{ $region->id }++;
            push @extra, $region;
        }
    }

    # Always re-sort via DFS post-order so that Phi regions are guaranteed
    # to precede their Phi nodes (region is a predecessor, not in inputs[]).
    my @all = grep { blessed($_) } ($base->@*, @extra);
    my %visited;
    my %in_progress;
    my @order;

    # Predecessors of a node are its inputs plus, for Phi, its region.
    my $predecessors = sub ($n) {
        my @preds = grep { defined $_ && blessed($_) } $n->inputs->@*;
        if ($n->operation eq 'Phi' && defined $n->region) {
            push @preds, $n->region;
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

        # Resolve inputs from already-created nodes
        my @inputs = map { $nodes[$_] } ($nd->{inputs} // [])->@*;

        # B::SoN serializes Return as inputs=[control, value] (control token
        # first). Chalk's contract is inputs=[value] with control carried in
        # control_in. Reconcile: when a Return leads with a CFG control node
        # (Start, or a Region/If/Proj/Loop merge from a control-flow body) and
        # has a trailing value, split off the control (re-attached via
        # control_in after construction below) and keep only the value as input.
        # Unwind is EXCLUDED: for a die, the Unwind is the real exit and must
        # stay a reachable input, not be demoted to control_in.
        my $bson_return_control;
        if ($op eq 'Return' && @inputs >= 2
                && blessed($inputs[0])
                && _is_cfg($inputs[0])
                && $inputs[0]->operation ne 'Unwind') {
            $bson_return_control = shift @inputs;
        }

        # A B::SoN void statement-effect Call leads with its control token
        # (inputs=[control, invocant, args]). Chalk's contract is
        # inputs=[invocant, args] with control carried in control_in, so it is
        # threaded into the effect chain (and survives DCE) instead of being an
        # orphaned data node whose side effect is lost. The producer only sets
        # is_stmt_effect when it prepended control, so inputs[0] IS the control
        # (a CFG node, or a preceding stmt-effect Call in a chain).
        my $bson_stmt_control;
        if ($op eq 'Call' && $fields->{is_stmt_effect}
                && @inputs >= 1 && blessed($inputs[0])) {
            $bson_stmt_control = shift @inputs;
        }

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

        my $node;
        if ($is_cfg) {
            $node = $factory->make_cfg($op, %args);
        }
        else {
            $node = $factory->make($op, %args);
        }

        # Re-attach a B::SoN Return's control token via control_in (it was split
        # out of inputs above to match Chalk's Return contract).
        if (defined $bson_return_control) {
            $node->set_control_in($bson_return_control);
        }

        # Re-attach a B::SoN void statement-effect Call's control token, threading
        # it into the effect chain (it was split out of inputs above).
        if (defined $bson_stmt_control) {
            $node->set_control_in($bson_stmt_control);
        }

        # Map a B::SoN stamp to a Chalk representation so the backend can lower
        # the node runtime-free. Chalk's own serializer emits no stamp, so this
        # only fires for B::SoN-produced JSON.
        if (defined $nd->{stamp} && exists $STAMP_TO_REPR{ $nd->{stamp} }) {
            $node->set_representation($STAMP_TO_REPR{ $nd->{stamp} });
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
    # merges Proj arms; the owning If/Loop is a Proj input's input.
    for my $node (@nodes) {
        next unless $node->operation eq 'Region';
        next if $node->head;
        my ($first_arm) = $node->inputs->@*;
        next unless defined $first_arm && blessed($first_arm)
            && $first_arm->operation eq 'Proj';
        my $owner = $first_arm->inputs->[0];
        $node->set_head($owner) if defined $owner && blessed($owner);
    }

    my $start   = $nodes[ $method_data->{start} ];
    my @returns = map { $nodes[$_] } $method_data->{returns}->@*;

    return Chalk::IR::Graph->new(start => $start, returns => \@returns);
}

# -----------------------------------------------------------------------
# from_json($json_string) — deserialize JSON to named Chalk::IR::Graph instances.
# -----------------------------------------------------------------------
sub from_json ($json_string) {
    my $data    = JSON::PP->new->decode($json_string);
    my %graphs;
    for my $name (sort keys $data->{methods}->%*) {
        $graphs{$name} = _deserialize_graph($data->{methods}{$name});
    }

    # 4c: a `classes` section (from B::SoN) is replayed into a sealed MOP.
    # The classes replay also seeds field-read reprs (which need the class
    # field types) before the universal pass runs.
    my $mop;
    if (ref $data->{classes} eq 'HASH' && %{ $data->{classes} }) {
        $mop = _replay_classes($data->{classes}, \%graphs);
    }

    # Universal repr-inference: seed aggregate/regex reprs and fixpoint-propagate
    # through computed + aggregate-read nodes for EVERY graph (class or not).
    # The backend requires a repr on these nodes to lower them (RC1).
    _seed_and_propagate_reprs(\%graphs);
    _stamp_method_call_reprs($data->{classes} // {}, \%graphs);

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

    # A :param field with no default has no declared type (the producer only
    # types a field from a constant default). Infer it from the CONSTRUCTOR
    # ARGUMENT before building the MOP: a Call(new) binds param_names[i] ->
    # inputs[i], so a field whose param_name matches carries the argument's
    # repr. Fill it onto the raw field record so BOTH declare_field (the MOP /
    # struct layout) and _stamp_field_access_reprs (the FieldAccess nodes) see
    # it. Cross-graph: the Call(new) is in the driver graph, the field in a
    # class section.
    my %ctor_arg_repr = _ctor_arg_reprs($graphs);
    for my $cname (keys %$classes) {
        for my $f (($classes->{$cname}{fields} // [])->@*) {
            next if defined $f->{type};
            my $pn = $f->{param_name} // next;
            my $repr = $ctor_arg_repr{"$cname\0$pn"} // next;
            $f->{type} = $repr;
        }
    }

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

            $cls->declare_field($vname,
                sigil      => substr($vname, 0, 1),
                param_name => $f->{param_name},
                attributes => \@attrs,
                (defined $f->{type} ? (type => $f->{type}) : ()),
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

    # Seed FieldAccess reprs from the declared field types. The universal
    # repr pass (_seed_and_propagate_reprs, run by from_json) then propagates
    # them through computed/aggregate nodes; method-Call reprs are stamped
    # afterward from the resolved callee's return repr.
    _stamp_field_access_reprs($classes, $graphs);

    return $mop;
}

# _propagate_computed_reprs(\%graphs) — fixpoint-propagate representations onto
# computed nodes whose inputs are now typed (e.g. a FieldAccess stamped from its
# field type feeds an Add). Mirrors the producer's result-stamp rules so a field
# read flowing into arithmetic carries a repr to the method body root.
my %_COMPUTED_REPR = (
    Add => 'join', Subtract => 'join', Multiply => 'join', Negate => 'join',
    Divide => 'Num', Power => 'Num', Modulo => 'Int',
    BitAnd => 'Int', BitOr => 'Int', BitXor => 'Int',
    LeftShift => 'Int', RightShift => 'Int', Complement => 'Int',
    Concat => 'Str', Length => 'Int',
    (map { $_ => 'Bool' } qw(
        NumEq NumLt NumGt NumLe NumGe NumNe StrEq StrLt StrGt StrLe StrGe StrNe)),
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
        for my $node ($g->nodes->@*) {
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

sub _propagate_computed_reprs ($graphs) {
    for my $g (values %$graphs) {
        my @nodes = $g->nodes->@*;
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

                # ref($obj) is modelled as Ref(Object) and lowers to the class
                # name -- a Str (backend _lower_ref_of_object). Only Ref over an
                # Object is this class-name case; Ref over a scalar (the \
                # operator) is a reference constructor and stays untyped here (an
                # honest GAP). Input-dependent, so it waits in the fixpoint until
                # the operand's Object repr is known (class-simple).
                if ($op eq 'Ref') {
                    my $in = $node->inputs->[0];
                    next unless defined $in && blessed($in)
                        && ($in->representation // '') eq 'Object';
                    $node->set_representation('Str');
                    $changed = 1;
                    next;
                }

                my $rule = $_COMPUTED_REPR{$op} // next;
                if ($rule ne 'join') {
                    $node->set_representation($rule);
                    $changed = 1;
                    next;
                }
                my @in = grep { defined && blessed($_) } $node->inputs->@*;
                my @reprs = map { $_->representation } @in;
                next if grep { !defined } @reprs;          # an input still untyped
                next if grep { !exists $_REPR_RANK{$_} } @reprs;
                my ($widest) = sort { $_REPR_RANK{$b} <=> $_REPR_RANK{$a} } @reprs;
                $node->set_representation($widest);
                $changed = 1;
            }
        }
    }
    return;
}

# _element_repr($container) — the element type of an ArrayRef/HashRef container,
# inferred as the widest element repr of its inputs. For a HashRef the inputs
# alternate key,value; the values are the odd positions. Returns undef when the
# element types are not yet known.
sub _element_repr ($container) {
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
    return undef if grep { !defined || !exists $_REPR_RANK{$_} } @reprs;
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

# _stamp_field_access_reprs($classes, \%graphs) — set each FieldAccess node's
# representation from its declared field type. The field type comes from the
# class section (4c-1b infers it from the field default); the backend needs a
# repr on the FieldAccess to lower a field read.
sub _stamp_field_access_reprs ($classes, $graphs) {
    # Build (class, fieldix) -> type from the class sections.
    my %field_type;
    for my $cname (keys %$classes) {
        for my $f (($classes->{$cname}{fields} // [])->@*) {
            next unless defined $f->{type};
            $field_type{"$cname\::" . ($f->{fieldix} // -1)} = $f->{type};
        }
    }

    for my $g (values %$graphs) {
        for my $node ($g->nodes->@*) {
            next unless $node->operation eq 'FieldAccess';
            next if defined $node->representation;
            my $stash = $node->field_stash // next;
            my $fidx  = $node->field_index;
            my $type  = $field_type{"$stash\::" . ($fidx // -1)} // next;
            $node->set_representation($type);
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
    }

    # Walk every graph's method Calls and stamp from the resolved callee.
    for my $g (values %$graphs) {
        for my $node ($g->nodes->@*) {
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
        }
    }
    return;
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
