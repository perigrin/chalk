# ABOUTME: NotMatch node for negated regex match operations
# ABOUTME: Represents $string !~ /pattern/ in the IR graph
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::NotMatch {
    field $left :param :reader;         # String to test against
    field $right :param :reader;        # Pattern to not match
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
        return [ $left->id, $right->id ];
    }

    method op() { 'NotMatch' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'NotMatch',
            inputs => $self->inputs,
            attributes => {
                left_id  => $left->id,
                right_id => $right->id,
            },
        };
    }

    method execute($context) {
        # Execute the not-match operation:
        # Evaluate left (string) and right (pattern)
        # Return true if pattern does NOT match

        # For now, return undef as placeholder
        # Full implementation requires regex compilation support
        return undef;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        # NotMatch cannot be constant-folded without knowing string value
        # Return self as-is
        return $self;
    }

    method record_transform(@args) {
        return;
    }
}

1;
