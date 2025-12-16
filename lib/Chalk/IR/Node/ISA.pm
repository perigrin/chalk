# ABOUTME: ISA comparison node in the IR graph
# ABOUTME: Represents isa type checking between a value and a class name
use 5.42.0;
use experimental qw(class);
use utf8;
use Chalk::IR::Type::Bool;

class Chalk::IR::Node::ISA {

    field $left :param :reader;
    field $right :param :reader;
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

    method op() { 'ISA' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'ISA',
            inputs => $self->inputs,
            attributes => {
                left_id  => $left->id,
                right_id => $right->id,
            },
        };
    }

    method execute($context) {
        my $left_val = $context->("node:" . $left->id);
        my $right_val = $context->("node:" . $right->id);

        # Runtime isa check: does $left_val isa $right_val?
        # In Perl, isa checks if value is an instance of class
        if (blessed($left_val)) {
            return $left_val->isa($right_val) ? true : false;
        }
        # Non-blessed value cannot pass isa check
        return false;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method compute() {
        # ISA type checking cannot be constant-folded without runtime info
        # Return Top (unknown) since we need runtime type information
        return Chalk::IR::Type::Top->top();
    }

    method peephole($graph = undef) {
        # ISA cannot be constant-folded without runtime type info
        # Return self as-is
        return $self;
    }

    method record_transform(@args) {
        return;
    }
}

1;
