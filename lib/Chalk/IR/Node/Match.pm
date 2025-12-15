# ABOUTME: Match node for regex match operations
# ABOUTME: Represents $string =~ /pattern/ in the IR graph
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Match {
    field $left :param :reader;         # String to match against
    field $right :param :reader;        # Pattern to match
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

    method op() { 'Match' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Match',
            inputs => $self->inputs,
            attributes => {
                left_id  => $left->id,
                right_id => $right->id,
            },
        };
    }

    method execute($context) {
        # Execute the match operation:
        # Evaluate left (string) and right (pattern)
        # Return match result (true/false or captures)

        # For now, return undef as placeholder
        # Full implementation requires regex compilation support
        return undef;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        # Match cannot be constant-folded without knowing string value
        # Return self as-is
        return $self;
    }

    method record_transform(@args) {
        return;
    }
}

1;
