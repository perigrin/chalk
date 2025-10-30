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

        # 2. Initialize value map
        my %values;

        # 3. Execute nodes in order
        for my $node (@schedule) {
            my $node_id = $node->id;
            my $op = $node->op;

            # Execute node (some nodes need values map, some don't)
            my $result;
            if ($op eq 'Start' || $op eq 'Constant') {
                $result = $node->execute();
            } elsif ($op =~ /^(Add|Subtract|Multiply|Divide|GT|LT|EQ|NE|GE|LE|Return)$/) {
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
        my $nodes = $graph->nodes;
        for my $node_id (keys %$nodes) {
            my $node = $nodes->{$node_id};
            return $node if $node->op eq 'Return';
        }
        die "No Return node found in graph";
    }
}

1;
