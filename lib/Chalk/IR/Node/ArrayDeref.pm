# ABOUTME: Array dereference node in the IR graph
# ABOUTME: Implements @$ref by dereferencing an array reference to get array contents
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::ArrayDeref {
    field $ref_id :param :reader;  # Node ID of the reference
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    # Dependency tracking for peephole re-optimization
    field $_deps = [];

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    method inputs() {
        return [$ref_id];
    }

    method op() { 'ArrayDeref' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'ArrayDeref',
            inputs => $self->inputs,
            attributes => {
                ref_id => $ref_id,
            },
        };
    }

    method execute($context) {
        # Get the reference object
        my $ref_obj = $context->("node:$ref_id");

        # If ref_obj is a blessed reference (Reference node result),
        # extract target context and label
        if (ref($ref_obj) eq 'HASH' && exists $ref_obj->{ref_context}) {
            my $target_context = $ref_obj->{ref_context};
            my $target_label = $ref_obj->{ref_label};

            # Perform lookup in the target context
            my $node_or_id = $target_context->($target_label);
            my $node_id = ref($node_or_id) ? $node_or_id->id : $node_or_id;

            # Resolve to get the actual array
            return $context->("node:$node_id");
        }

        # If ref_obj is already an array reference, dereference it
        if (ref($ref_obj) eq 'ARRAY') {
            return $ref_obj;
        }

        # Fallback: return as-is
        return $ref_obj;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        return $self;
    }

    method record_transform(@args) {
        return;
    }
}

1;
