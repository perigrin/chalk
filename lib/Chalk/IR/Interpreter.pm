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

            # Execute node (dispatch based on signature)
            my $result;
            if ($op eq 'Start' || $op eq 'Constant') {
                $result = $node->execute();
            } elsif ($op =~ /^(Store|Load)$/) {
                $result = $node->execute(\%values, \%heap);
            } elsif ($op =~ /^(Add|Subtract|Multiply|Divide|GT|LT|EQ|NE|GE|LE|Negate|If|Proj|Region|Phi|Return)$/) {
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
        for my $node_id (keys %$nodes) {
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
                # Extract numeric part from node_N
                my ($id) = $node->id =~ /(\d+)$/;
                my ($best_id) = $best->id =~ /(\d+)$/;
                $best = $node if defined($id) && defined($best_id) && $id > $best_id;
            }
            return $best;
        }

        # Fallback: return first one (but this shouldn't happen in well-formed programs)
        return $return_nodes[0];
    }
}

1;
