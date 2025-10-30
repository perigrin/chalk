# ABOUTME: Sea of Nodes IR graph container for Chalk compiler
# ABOUTME: Manages collection of IR nodes and provides JSON serialization for IR persistence
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::IR::Graph {
    use Chalk::IR::Node;

    field $nodes :reader;
    field $entry :reader;
    field $uses;  # Use-def map: node_id => [user_id1, user_id2, ...]

    ADJUST {
        $nodes = {};
        $entry = undef;
        $uses  = {};
    }

    method add_node($node) {
        my $node_id = $node->id;
        $nodes->{$node_id} = $node;

        # Initialize use list for this node (empty initially)
        $uses->{$node_id} //= [];

        # Update use-def chains: for each input, add this node as a user
        for my $input_id ( $node->inputs->@* ) {
            next unless defined $input_id;  # Skip undefined inputs
            $uses->{$input_id} //= [];
            push $uses->{$input_id}->@*, $node_id;
        }

        # First node added becomes entry point
        $entry //= $node_id;

        return;
    }

    method get_node($id) {
        return $nodes->{$id};
    }

    method get_uses($id) {
        return $uses->{$id} // [];
    }

    method node_count() {
        return scalar keys %{$nodes};
    }

    method set_entry($new_entry) {
        $entry = $new_entry;
        return;
    }

    method to_json() {
        my @node_list = map { $_->to_hash() } values %{$nodes};

        return {
            version => '1.0',
            entry   => $entry,
            nodes   => \@node_list,
        };
    }

    sub from_json( $class, $json ) {
        my $graph = $class->new();

        # Restore nodes in order
        for my $node_data ( $json->{nodes}->@* ) {
            my $node = Chalk::IR::Node->new(
                id         => $node_data->{id},
                op         => $node_data->{op},
                inputs     => $node_data->{inputs},
                attributes => $node_data->{attributes},
            );
            $graph->add_node($node);
        }

        # Set entry explicitly (in case it's not the first node)
        $graph->set_entry( $json->{entry} );

        return $graph;
    }

    # Linearize graph using topological sort
    # Returns array of nodes in execution order
    method linearize() {
        my @result;
        my %visited;
        my %in_progress;

        # Depth-first search for topological sort
        my $visit;
        $visit = sub {
            my ($node_id) = @_;
            return if $visited{$node_id};

            # Detect cycles
            die "Cycle detected at node $node_id" if $in_progress{$node_id};
            $in_progress{$node_id} = 1;

            my $node = $nodes->{$node_id};
            if ($node) {
                # Visit all dependencies (inputs) first
                for my $input_id ($node->inputs->@*) {
                    next unless defined $input_id;
                    next if $input_id eq '__CONTROL_PLACEHOLDER__';
                    $visit->($input_id);
                }
            }

            delete $in_progress{$node_id};
            $visited{$node_id} = 1;

            # Add node after all its dependencies
            push @result, $node if $node;
        };

        # Visit all nodes in the graph (not just from entry)
        # This ensures we get all nodes including those not reachable from entry
        my @node_ids = keys $nodes->%*;
        for my $node_id (@node_ids) {
            $visit->($node_id);
        }

        return @result;
    }
}

1;
