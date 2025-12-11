# ABOUTME: Worklist-based iterative peephole optimization pass for Sea of Nodes IR
# ABOUTME: Iterates peephole optimizations until fixed point (no more changes occur)

use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Optimizer::IterPeeps {

    # Instance method for pipeline compatibility
    # Returns optimized graph (not a hashref)
    method apply($graph) {
        my $result = $self->run_iterpeeps($graph);
        return $result->{graph};
    }

    # Compute value number for a node (for GVN table lookup)
    method _compute_value_number($node, $node_to_value, $graph) {
        my $op = $node->op;
        my $attrs = $node->attributes;

        # Special case: Constants
        if ($op eq 'Constant') {
            my $value = $attrs->{value} // '';
            my $type = $attrs->{type} // '';
            return "Constant:$value:$type";
        }

        # Special case: Proj nodes (include index)
        if ($op eq 'Proj') {
            my $index = $attrs->{index} // '';
            my @input_vns;
            for my $input_id ($node->inputs->@*) {
                if (defined($input_id) && exists($node_to_value->{$input_id})) {
                    push @input_vns, $node_to_value->{$input_id};
                } else {
                    push @input_vns, $input_id // 'undef';
                }
            }
            my $inputs_str = join(',', @input_vns);
            return "Proj:$index:$inputs_str";
        }

        # Special case: Phi nodes - use identity-based comparison
        if ($op eq 'Phi') {
            my $inputs_str = join(',', map { $_ // 'undef' } $node->inputs->@*);
            my $region_id = $attrs->{region_id} // '';
            return "Phi:$region_id:$inputs_str";
        }

        # General case: Operations - get value numbers of inputs
        my @input_vns;
        for my $input_id ($node->inputs->@*) {
            if (defined($input_id) && exists($node_to_value->{$input_id})) {
                push @input_vns, $node_to_value->{$input_id};
            } else {
                push @input_vns, $input_id // 'undef';
            }
        }

        # Handle commutativity for Add and Multiply
        if ($op eq 'Add' || $op eq 'Multiply') {
            @input_vns = sort @input_vns;
        }

        my $inputs_str = join(',', @input_vns);
        return "$op:$inputs_str";
    }

    # GVN table lookup - returns existing node or undef
    method _gvn_lookup($node, $gvn_table, $node_to_value, $graph) {
        my $value_num = $self->_compute_value_number($node, $node_to_value, $graph);
        return $gvn_table->{$value_num};
    }

    # Insert node into GVN table
    method _gvn_insert($node, $gvn_table, $node_to_value, $graph) {
        my $value_num = $self->_compute_value_number($node, $node_to_value, $graph);
        $gvn_table->{$value_num} = $node->id unless exists($gvn_table->{$value_num});
        $node_to_value->{$node->id} = $value_num;
    }

    # Remove node from GVN table
    method _gvn_remove($node, $gvn_table, $node_to_value, $graph) {
        my $value_num = $self->_compute_value_number($node, $node_to_value, $graph);
        if (exists($gvn_table->{$value_num}) && $gvn_table->{$value_num} eq $node->id) {
            delete $gvn_table->{$value_num};
        }
        delete $node_to_value->{$node->id};
    }

    # Replace node in GVN table (remove old, insert new)
    method _gvn_replace($old_node, $new_node, $gvn_table, $node_to_value, $graph) {
        $self->_gvn_remove($old_node, $gvn_table, $node_to_value, $graph);
        $self->_gvn_insert($new_node, $gvn_table, $node_to_value, $graph);
    }

    # Run iterative peephole optimization pass with integrated GVN
    # Returns: { graph => optimized_graph, metrics => { iterations => N, peepholes_applied => N, gvn_hits => N } }
    method run_iterpeeps($graph) {
        my $peepholes_applied = 0;
        my $gvn_hits = 0;
        my $iterations = 0;

        # GVN table: value_number => canonical_node_id
        my %gvn_table;
        my %node_to_value;

        # Initialize worklist with all node IDs
        my @worklist = keys($graph->nodes->%*);
        my %in_worklist = map { $_ => 1 } @worklist;

        # Pre-populate GVN table with existing nodes
        for my $node_id (@worklist) {
            my $node = $graph->get_node($node_id);
            next unless defined($node);
            $self->_gvn_insert($node, \%gvn_table, \%node_to_value, $graph);
        }

        # Track replacements: old_node_id => new_node
        my %replacements;

        while (@worklist) {
            $iterations++;
            my $node_id = shift @worklist;
            delete $in_worklist{$node_id};

            my $node = $graph->get_node($node_id);
            next unless defined($node);

            # Skip nodes that can't be peepholed
            next unless $node->can('peephole');

            # Apply peephole optimization
            my $optimized = $node->peephole($graph);

            # Check if optimization produced a different node
            if ($optimized && $optimized->id ne $node_id) {
                $peepholes_applied++;

                # Check if optimized node matches something in GVN table
                my $gvn_match_id = $self->_gvn_lookup($optimized, \%gvn_table, \%node_to_value, $graph);

                if ($gvn_match_id && $gvn_match_id ne $optimized->id) {
                    # GVN hit! Use existing node instead
                    $gvn_hits++;
                    my $gvn_match = $graph->get_node($gvn_match_id);
                    if ($gvn_match) {
                        # TODO: Merge types with join() if nodes have type info
                        $optimized = $gvn_match;
                    }
                }

                # Track the replacement
                $replacements{$node_id} = $optimized;

                # Update GVN table
                $self->_gvn_replace($node, $optimized, \%gvn_table, \%node_to_value, $graph);

                # Add the replacement node to the graph if not already there
                unless ($graph->get_node($optimized->id)) {
                    $graph->add_node($optimized);
                    $self->_gvn_insert($optimized, \%gvn_table, \%node_to_value, $graph);
                }

                # Add users of the old node to worklist for re-optimization
                my $users = $graph->get_uses($node_id);
                for my $user_id ($users->@*) {
                    unless ($in_worklist{$user_id}) {
                        push @worklist, $user_id;
                        $in_worklist{$user_id} = 1;
                    }
                }

                # Add dependents (from dependency tracking) to worklist
                for my $dep_id ($node->get_deps()) {
                    unless ($in_worklist{$dep_id}) {
                        push @worklist, $dep_id;
                        $in_worklist{$dep_id} = 1;
                    }
                }

                # Also add the new node to worklist (it might optimize further)
                unless ($in_worklist{$optimized->id}) {
                    push @worklist, $optimized->id;
                    $in_worklist{$optimized->id} = 1;
                }
            }
        }

        # Phase 2: Apply replacements to create final graph
        if (%replacements) {
            $graph = $self->_apply_replacements($graph, \%replacements);
        }

        return {
            graph => $graph,
            metrics => {
                iterations => $iterations,
                peepholes_applied => $peepholes_applied,
                gvn_hits => $gvn_hits,
            }
        };
    }

    # Apply node replacements to the graph
    # Updates all references from old nodes to new nodes
    method _apply_replacements($graph, $replacements) {
        # Build final redirection map (follow chains)
        my %final_redirect;
        for my $old_id (keys $replacements->%*) {
            my $new_node = $replacements->{$old_id};
            my $new_id = $new_node->id;

            # Follow replacement chain to final destination
            while (exists($replacements->{$new_id})) {
                $new_node = $replacements->{$new_id};
                $new_id = $new_node->id;
            }
            $final_redirect{$old_id} = $new_id;
        }

        # Build new graph with updated references
        my $new_graph = Chalk::IR::Graph->new();
        my @node_ids = sort keys($graph->nodes->%*);

        for my $node_id (@node_ids) {
            # Skip nodes that were replaced (unless they're the final destination)
            if (exists($final_redirect{$node_id})) {
                # Only skip if this node is not the final destination of some chain
                my $is_final_dest = 0;
                for my $dest_id (values %final_redirect) {
                    if ($dest_id eq $node_id) {
                        $is_final_dest = 1;
                        last;
                    }
                }
                next unless $is_final_dest;
            }

            my $node = $graph->get_node($node_id);
            next unless defined($node);

            # Update inputs to use replacement nodes
            my @new_inputs;
            my $inputs_changed = 0;
            for my $input_id ($node->inputs->@*) {
                if (defined($input_id) && exists($final_redirect{$input_id})) {
                    push @new_inputs, $final_redirect{$input_id};
                    $inputs_changed = 1;
                } else {
                    push @new_inputs, $input_id;
                }
            }

            # If inputs changed, create a new node with updated inputs
            if ($inputs_changed) {
                my $new_node = Chalk::IR::Node->from_hash({
                    id => $node_id,
                    op => $node->op,
                    inputs => \@new_inputs,
                    attributes => $self->_redirect_attributes($node->attributes, \%final_redirect),
                    source_info => $node->source_info,
                    transform_chain => $node->transform_chain // [],
                });
                $new_graph->add_node($new_node);
            } else {
                $new_graph->add_node($node);
            }
        }

        # Preserve entry point (following any redirection)
        if (defined($graph->entry)) {
            my $new_entry = $graph->entry;
            if (exists($final_redirect{$new_entry})) {
                $new_entry = $final_redirect{$new_entry};
            }
            $new_graph->set_entry($new_entry);
        }

        return $new_graph;
    }

    # Apply redirections to node attributes (which may contain node references)
    method _redirect_attributes($attrs, $redirections) {
        return {} unless defined($attrs);

        my %new_attrs;

        for my $key (keys($attrs->%*)) {
            my $value = $attrs->{$key};

            # Special case: any attribute ending in _id is a node reference
            if (length($key) >= 3 && substr($key, -3) eq '_id' && defined($value) && exists($redirections->{$value})) {
                $new_attrs{$key} = $redirections->{$value};
            } else {
                $new_attrs{$key} = $value;
            }
        }

        return \%new_attrs;
    }
}

1;
