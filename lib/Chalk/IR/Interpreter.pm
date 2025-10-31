# ABOUTME: Threaded interpreter for executing Sea of Nodes IR graphs
# ABOUTME: Linearizes graph, executes nodes in topological order, returns result
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Interpreter {
    field $graph :param :reader;

    method execute() {
        # 1. Linearize graph to get execution order
        my @schedule = $graph->linearize();

        # 2. Initialize value map and heap
        my %values;
        my %heap;

        # 3. Execute nodes in order
        for my $node (@schedule) {
            my $node_id = $node->id;
            my $op = $node->op;

            # Dispatch based on node execute() signature
            # Different node types take different arguments
            my %heap_ops = ( Store => 1, Load => 1 );
            my %value_ops = (
                Add => 1, Subtract => 1, Multiply => 1, Divide => 1,
                GT => 1, LT => 1, EQ => 1, NE => 1, GE => 1, LE => 1,
                Negate => 1, Not => 1, If => 1, Proj => 1, Region => 1, Phi => 1, Return => 1, Loop => 1, Reference => 1
            );
            my %simple_ops = ( Start => 1, Constant => 1 );

            # Execute node with appropriate arguments
            my $result;
            if ($simple_ops{$op}) {
                $result = $node->execute();
            } elsif ($heap_ops{$op}) {
                $result = $node->execute(\%values, \%heap);
            } elsif ($value_ops{$op}) {
                $result = $node->execute(\%values);
            } else {
                die "Unknown op type: $op";
            }

            $values{$node_id} = $result;
        }

        # 4. Find Return node and extract its value
        my $return_node = $self->find_return();
        return $values{$return_node->id};
    }

    method find_return() {
        # Find the Return node in the graph
        # Prefer explicit return statements (with __CONTROL_PLACEHOLDER__) over implicit returns
        # When multiple explicit returns exist (from parser intermediate states),
        # choose the one with the highest node ID (most recently created)
        my $nodes = $graph->nodes;

        my @return_nodes;
        # Parser compat: keys() requires parentheses around argument
        my @node_ids = keys($nodes->%*);
        for my $node_id (@node_ids) {
            my $node = $nodes->{$node_id};
            push @return_nodes, $node if $node->op eq 'Return';
        }

        die "No Return node found in graph" unless @return_nodes;

        # If only one Return, use it
        return $return_nodes[0] if @return_nodes == 1;

        # Multiple Returns - prefer explicit return statements
        # (those with __CONTROL_PLACEHOLDER__ as control input)
        my @explicit_returns;
        for my $node (@return_nodes) {
            my @inputs = $node->inputs->@*;
            if (@inputs > 0 && defined($inputs[0]) && $inputs[0] eq '__CONTROL_PLACEHOLDER__') {
                push @explicit_returns, $node;
            }
        }

        # If we found explicit returns, use the one with highest ID (most recent)
        if (@explicit_returns) {
            my $best = $explicit_returns[0];
            for my $node (@explicit_returns) {
                # Extract numeric part from node_N format
                # node_42 -> 42 (skip first 5 chars: "node_")
                my $node_id_str = $node->id;
                my $best_id_str = $best->id;

                my $id = substr($node_id_str, 5);
                my $best_id = substr($best_id_str, 5);

                $best = $node if $id > $best_id;
            }
            return $best;
        }

        # Multiple Return nodes but none are explicit - this indicates malformed IR
        my @return_ids = map { $_->id } @return_nodes;
        my $ids_str = join(', ', @return_ids);
        die "Malformed IR graph: found multiple Return nodes ($ids_str) " .
            "but none have __CONTROL_PLACEHOLDER__ control input. " .
            "This indicates incorrect IR construction - each Return must be " .
            "properly linked to control flow.";
    }
}

1;
