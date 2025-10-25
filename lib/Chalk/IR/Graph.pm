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
        return scalar keys $nodes->%*;
    }

    method set_entry($new_entry) {
        $entry = $new_entry;
        return;
    }

    method prune_by_derivation_id($winning_deriv_id) {
        # Remove all nodes that don't have the winning derivation ID
        my %nodes_to_keep;
        my %uses_to_keep;

        # Find all nodes with the winning derivation ID
        for my $node_id (keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            my $node_deriv_id = $node->derivation_id;

            # Keep nodes with the winning derivation ID, or nodes with no derivation ID (shouldn't happen)
            if (!defined($node_deriv_id) || $node_deriv_id eq $winning_deriv_id) {
                $nodes_to_keep{$node_id} = $node;
            }
        }

        # Rebuild uses map for kept nodes
        for my $node_id (keys %nodes_to_keep) {
            my $node = $nodes_to_keep{$node_id};
            $uses_to_keep{$node_id} //= [];

            for my $input_id ( $node->inputs->@* ) {
                next unless defined $input_id;
                # Only add use if the input is also being kept
                if (exists $nodes_to_keep{$input_id}) {
                    $uses_to_keep{$input_id} //= [];
                    push $uses_to_keep{$input_id}->@*, $node_id;
                }
            }
        }

        # Replace nodes and uses with pruned versions
        $nodes = \%nodes_to_keep;
        $uses = \%uses_to_keep;

        # Update entry to first Start node with winning derivation ID
        for my $node_id (keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            if ($node->op eq 'Start') {
                $entry = $node_id;
                last;
            }
        }

        return;
    }

    method to_json() {
        my @node_list = map { $_->to_hash() } values $nodes->%*;

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
}

1;
