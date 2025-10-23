# ABOUTME: Sea of Nodes IR graph container for Chalk compiler
# ABOUTME: Manages collection of IR nodes and provides JSON serialization for IR persistence
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::IR::Graph {
    use Chalk::IR::Node;

    field $nodes :reader;
    field $entry :reader;

    ADJUST {
        $nodes = {};
        $entry = undef;
    }

    method add_node($node) {
        my $node_id = $node->id;
        $nodes->{$node_id} = $node;

        # First node added becomes entry point
        $entry //= $node_id;

        return;
    }

    method get_node($id) {
        return $nodes->{$id};
    }

    method node_count() {
        return scalar keys $nodes->%*;
    }

    method set_entry($new_entry) {
        $entry = $new_entry;
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
