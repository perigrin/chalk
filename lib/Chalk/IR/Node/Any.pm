# ABOUTME: Any node for testing if any element satisfies a predicate
# ABOUTME: Represents any { block } @list in the IR graph
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Any {
    field $block :param :reader;        # Block/predicate to test each element
    field $list :param :reader;         # List to test
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
        my @inputs;
        push @inputs, $block->id if defined $block && $block->can('id');
        push @inputs, $list->id if defined $list && $list->can('id');
        return \@inputs;
    }

    method op() { 'Any' }

    method to_hash() {
        my $block_id = (defined $block && $block->can('id')) ? $block->id : undef;
        my $list_id = (defined $list && $list->can('id')) ? $list->id : undef;

        return {
            id     => $self->id,
            op     => 'Any',
            inputs => $self->inputs,
            attributes => {
                block_id => $block_id,
                list_id  => $list_id,
            },
        };
    }

    method execute($context) {
        # Execute the any operation:
        # 1. Get the list value
        # 2. Apply block to each element
        # 3. Return true if any element satisfies predicate, false otherwise

        # For now, return undef as placeholder
        # Full implementation requires CEK machine integration
        return undef;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        # Any cannot be constant-folded without knowing block behavior
        # Return self as-is
        return $self;
    }

    method record_transform(@args) {
        return;
    }
}

1;
