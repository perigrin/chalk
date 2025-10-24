# ABOUTME: Global Value Numbering optimization pass for Sea of Nodes IR
# ABOUTME: Implements GVN for common subexpression elimination and redundant computation removal

use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::IR::Optimizer::GVN {
    use Chalk::IR::Node;
    use Chalk::IR::Graph;

    # Run Global Value Numbering optimization pass
    # Returns: { graph => optimized_graph, metrics => { nodes_eliminated => N, redirections => {...} } }
    sub run_gvn($class, $graph) {
        # Value number tracking: value_number => canonical_node_id
        my $value_to_node = {};

        # Node to value number mapping: node_id => value_number
        my $node_to_value = {};

        # Redirection map: duplicate_node_id => canonical_node_id
        my $redirections = {};

        # Get all nodes in a consistent order (we'll process them by ID order)
        my @node_ids = sort keys %{$graph->nodes};

        # Phase 1: Compute value numbers for all nodes
        for my $node_id (@node_ids) {
            my $node = $graph->get_node($node_id);
            next unless defined($node);

            # Compute value number for this node
            my $value_num = $class->_compute_value_number($node, $node_to_value, $graph);

            # Check if we've seen this value number before
            if (exists($value_to_node->{$value_num})) {
                # Found a duplicate! Record the redirection
                my $canonical_id = $value_to_node->{$value_num};
                $redirections->{$node_id} = $canonical_id;
                # Use the canonical node's value number for this node too
                $node_to_value->{$node_id} = $value_num;
            } else {
                # First time seeing this value - this is the canonical node
                $value_to_node->{$value_num} = $node_id;
                $node_to_value->{$node_id} = $value_num;
            }
        }

        # Phase 2: Build new graph with redirections applied
        my $new_graph = Chalk::IR::Graph->new();

        # Track which nodes have been copied to new graph
        my %copied;

        # Copy nodes that aren't redirected, applying redirections to inputs
        for my $node_id (@node_ids) {
            # Skip nodes that are being redirected away
            next if exists($redirections->{$node_id});

            my $old_node = $graph->get_node($node_id);
            next unless defined($old_node);

            # Apply redirections to input list
            my @new_inputs;
            for my $input_id ($old_node->inputs->@*) {
                if (defined($input_id)) {
                    # Follow redirection chain if this input was redirected
                    my $final_id = $class->_follow_redirections($input_id, $redirections);
                    push @new_inputs, $final_id;
                } else {
                    push @new_inputs, undef;
                }
            }

            # Apply redirections to attributes (if they contain node references)
            my $new_attributes = $class->_redirect_attributes(
                $old_node->attributes,
                $redirections
            );

            # Create new node with redirected inputs
            my $new_node = Chalk::IR::Node->new(
                id         => $node_id,
                op         => $old_node->op,
                inputs     => \@new_inputs,
                attributes => $new_attributes,
            );

            $new_graph->add_node($new_node);
            $copied{$node_id} = 1;
        }

        # Preserve entry point (following any redirection)
        if (defined($graph->entry)) {
            my $new_entry = $class->_follow_redirections($graph->entry, $redirections);
            $new_graph->set_entry($new_entry);
        }

        # Compute metrics
        my $nodes_eliminated = scalar keys %{$redirections};

        return {
            graph => $new_graph,
            metrics => {
                nodes_eliminated => $nodes_eliminated,
                redirections => $redirections,
            }
        };
    }

    # Compute value number for a node
    # Returns a string that uniquely identifies the value computed by this node
    sub _compute_value_number($class, $node, $node_to_value, $graph) {
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
            # Get value number of input node
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
        # Only merge if ALL inputs are identical
        if ($op eq 'Phi') {
            # For Phi nodes, we use the actual input IDs rather than value numbers
            # This is conservative but correct
            my $inputs_str = join(',', map { $_ // 'undef' } $node->inputs->@*);
            my $region_id = $attrs->{region_id} // '';
            return "Phi:$region_id:$inputs_str";
        }

        # General case: Operations
        # Get value numbers of inputs
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

    # Follow a chain of redirections to find the final canonical node
    sub _follow_redirections($class, $node_id, $redirections) {
        my $current = $node_id;
        my %seen;

        while (exists($redirections->{$current})) {
            # Detect cycles (shouldn't happen, but be safe)
            return $node_id if exists($seen{$current});
            $seen{$current} = 1;

            $current = $redirections->{$current};
        }

        return $current;
    }

    # Apply redirections to node attributes (which may contain node references)
    sub _redirect_attributes($class, $attrs, $redirections) {
        return {} unless defined($attrs);

        my %new_attrs;

        for my $key (keys( $attrs->%* )) {
            my $value = $attrs->{$key};

            # If this is a hash ref, it might be a NodeRef
            if (ref($value) eq 'HASH') {
                # Check if it's a NodeRef
                if (exists($value->{op}) && $value->{op} eq 'NodeRef') {
                    my $node_id = $value->{node_id};
                    if (defined($node_id) && exists($redirections->{$node_id})) {
                        # Redirect the NodeRef
                        $new_attrs{$key} = {
                            $value->%*,
                            node_id => $redirections->{$node_id}
                        };
                    } else {
                        $new_attrs{$key} = $value;
                    }
                } else {
                    # Just copy the hash as-is
                    $new_attrs{$key} = $value;
                }
            }
            # Special case: store_id attribute (used in Load nodes)
            elsif ($key eq 'store_id' && defined($value) && exists($redirections->{$value})) {
                $new_attrs{$key} = $redirections->{$value};
            }
            # Special case: region_id attribute (used in Phi nodes)
            elsif ($key eq 'region_id' && defined($value) && exists($redirections->{$value})) {
                $new_attrs{$key} = $redirections->{$value};
            }
            else {
                # Copy as-is for other types
                $new_attrs{$key} = $value;
            }
        }

        return \%new_attrs;
    }
}

1;
