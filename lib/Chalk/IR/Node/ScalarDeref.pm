# ABOUTME: Scalar dereference node in the IR graph
# ABOUTME: Implements $$ref by performing context lookup via reference's (context, label) pair
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::ScalarDeref :isa(Chalk::IR::Node::Base) {
    field $ref_id :param :reader;  # Node ID of the reference

    method op() { 'ScalarDeref' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'ScalarDeref',
            inputs => $self->inputs,
            attributes => {
                ref_id => $ref_id,
            },
        };
    }

    method execute($context) {
        # Get the reference object
        my $ref_obj = $context->("node:$ref_id");

        # Extract the target context and label from the reference
        my $target_context = $ref_obj->{ref_context};
        my $target_label = $ref_obj->{ref_label};

        # Perform lookup in the target context (might get node object or node ID)
        my $node_or_id = $target_context->($target_label);

        # Get the node ID (handle both node objects and IDs)
        my $node_id = ref($node_or_id) ? $node_or_id->id : $node_or_id;

        # Resolve the node ID to get the actual value
        my $value = $context->("node:$node_id");

        return $value;
    }
}

1;
