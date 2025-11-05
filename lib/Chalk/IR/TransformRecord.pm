# ABOUTME: Record of a single transformation that created or modified an IR node
# ABOUTME: Tracks operation type, source node ID, timestamp, and context for debugging
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::TransformRecord {
    field $operation      :param :reader;  # Type of transformation (e.g., 'semantic_action', 'optimization')
    field $name           :param :reader;  # Name of rule/optimizer that performed transformation
    field $source_node_id :param :reader = undef;  # ID of source IR node (avoids circular references)
    field $timestamp      :param :reader;  # When transformation occurred
    field $context        :param :reader = undef;  # Additional context information

    # Format transformation record for display
    method to_string() {
        my $str = "$operation: $name";

        if ($source_node_id) {
            $str .= " (from node $source_node_id)";
        }

        if ($context) {
            $str .= " - $context";
        }

        $str .= " at " . localtime($timestamp);

        return $str;
    }

    # Convert to hash for serialization
    method to_hash() {
        return {
            operation      => $operation,
            name           => $name,
            source_node_id => $source_node_id,
            timestamp      => $timestamp,
            context        => $context,
        };
    }
}

1;
