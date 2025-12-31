# ABOUTME: All node for testing if all elements satisfy a predicate
# ABOUTME: Represents all { block } @list in the IR graph
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::All {
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

    method op() { 'All' }

    method to_hash() {
        my $block_id = (defined $block && $block->can('id')) ? $block->id : undef;
        my $list_id = (defined $list && $list->can('id')) ? $list->id : undef;

        return {
            id     => $self->id,
            op     => 'All',
            inputs => $self->inputs,
            attributes => {
                block_id => $block_id,
                list_id  => $list_id,
            },
        };
    }

    method execute($context) {
        # Execute the all operation:
        # 1. Get the list value
        # 2. Apply block to each element
        # 3. Return true if all elements satisfy predicate, false otherwise

        # For now, return undef as placeholder
        # Full implementation requires CEK machine integration
        return undef;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        # All cannot be constant-folded without knowing block behavior
        # Return self as-is
        return $self;
    }

    method record_transform(@args) {
        return;
    }
}

1;
