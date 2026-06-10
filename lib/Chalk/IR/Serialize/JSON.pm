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

    for my $nd (@node_data) {
        my $op     = $nd->{op};
        my $fields = $nd->{fields} // {};
        my $is_cfg = $nd->{cfg}    // 0;

        # Resolve inputs from already-created nodes
        my @inputs = map { $nodes[$_] } ($nd->{inputs} // [])->@*;

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
        }
        elsif ($op eq 'Phi') {
            $args{region} = $nodes[ $fields->{region} ];
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

        push @nodes, $node;
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
    return \%graphs;
}

1;
