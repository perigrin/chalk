# ABOUTME: Dead Code Elimination optimization pass for Sea of Nodes IR
# ABOUTME: Removes unreachable control flow, dead branches, and unused computations
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Optimizer::DCE {

    # Instance method for pipeline compatibility
    # Returns optimized graph (not a hashref)
    method apply($graph) {
        my $result = $self->run_dce($graph);
        return $result->{graph};
    }

    # Run Dead Code Elimination optimization pass
    # Returns: { graph => optimized_graph, metrics => { nodes_eliminated => N, peepholes_applied => N } }
    method run_dce($graph) {
        my $nodes_eliminated = 0;
        my $peepholes_applied = 0;

        # Phase 1: Apply peephole optimizations to all nodes
        # This detects constant conditions and dead branches
        my %replacements;
        my @node_ids = sort keys %{$graph->nodes};

        for my $node_id (@node_ids) {
            my $node = $graph->get_node($node_id);
            next unless defined($node);

            # Apply peephole optimization if available
            if ($node->can('peephole')) {
                my $optimized = $node->peephole($graph);
                if ($optimized && $optimized->id ne $node_id) {
                    # Node was replaced - track the replacement
                    $replacements{$node_id} = $optimized->id;
                    $peepholes_applied++;

                    # Add the replacement node to the graph if it's not there
                    unless ($graph->get_node($optimized->id)) {
                        $graph->add_node($optimized);
                    }
                }
            }
        }

        # Phase 2: Update inputs to use replacements
        @node_ids = sort keys %{$graph->nodes};
        for my $node_id (@node_ids) {
            my $node = $graph->get_node($node_id);
            next unless defined($node);

            my @inputs = $node->inputs->@*;
            my $changed = 0;
            for my $i (0 .. $#inputs) {
                if (defined($inputs[$i]) && exists($replacements{$inputs[$i]})) {
                    $inputs[$i] = $replacements{$inputs[$i]};
                    $changed = 1;
                }
            }

            if ($changed) {
                # Update node inputs - we need to reconstruct the node
                # This is a limitation of the current immutable design
                # For now, we track that inputs would change
            }
        }

        # Phase 3: Remove dead nodes using the graph's kill mechanism
        # Mark all reachable nodes from entry point
        my %reachable;
        my @worklist;

        # Start from entry point if available
        if (defined($graph->entry)) {
            push @worklist, $graph->entry;
        }

        # Also start from any Return nodes (they are always reachable)
        for my $node_id (keys %{$graph->nodes}) {
            my $node = $graph->get_node($node_id);
            next unless defined($node);
            if ($node->op eq 'Return') {
                push @worklist, $node_id;
            }
        }

        # Mark reachability
        while (@worklist) {
            my $node_id = shift @worklist;
            next if exists($reachable{$node_id});
            $reachable{$node_id} = 1;

            my $node = $graph->get_node($node_id);
            next unless defined($node);

            # Add all inputs to worklist
            for my $input_id ($node->inputs->@*) {
                next unless defined($input_id);
                push @worklist, $input_id unless exists($reachable{$input_id});
            }

            # Add attribute references to worklist
            my $attrs = $node->attributes;
            if ($attrs) {
                for my $key (keys $attrs->%*) {
                    # Handle _id suffixed attributes
                    if (length($key) >= 3 && substr($key, -3) eq '_id') {
                        my $ref_id = $attrs->{$key};
                        if (defined($ref_id) && !exists($reachable{$ref_id})) {
                            push @worklist, $ref_id;
                        }
                    }
                }
            }
        }

        # Remove unreachable nodes
        for my $node_id (keys %{$graph->nodes}) {
            unless (exists($reachable{$node_id})) {
                $graph->remove_node($node_id);
                $nodes_eliminated++;
            }
        }

        return {
            graph => $graph,
            metrics => {
                nodes_eliminated => $nodes_eliminated,
                peepholes_applied => $peepholes_applied,
            }
        };
    }
}

1;
