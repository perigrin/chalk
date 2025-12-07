# ABOUTME: Constant value node in the IR graph
# ABOUTME: Represents compile-time constant values (integers, strings, etc.)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Constant {
    use Chalk::IR::Type::Integer;
    use Chalk::IR::Type::Bool;

    field $value :param :reader;
    field $type  :param :reader;  # Must be a Type object (TypeInteger, TypeFloat, TypeBool, etc.)
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    # Dependency tracking for peephole re-optimization
    field $_deps = [];

    ADJUST {
        use Chalk::IR::Type;
        use Chalk::Grammar::Chalk::Type;
        # Ensure type is a Type object (either IR or Grammar type hierarchy)
        unless ($type isa Chalk::IR::Type || $type isa Chalk::Grammar::Chalk::Type) {
            die "Constant type must be a Type object (Chalk::IR::Type or Chalk::Grammar::Chalk::Type), got: " . (ref($type) || "'$type'");
        }
    }

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    # No inputs for constants (leaf nodes)
    method inputs() { return []; }

    method op() { 'Constant' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Constant',
            inputs => [],
            attributes => {
                value => $value,
                type  => $type,
            },
        };
    }

    method execute($context = undef) {
        # Constant doesn't need context, but accept it for signature compatibility
        return $value;
    }

    # Compatibility methods for code expecting Base methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        return $self;
    }

    # Return type for constant folding - constants always have known type
    method compute() {
        # Type is always a Type object (enforced by ADJUST)
        return $type;
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

}

1;
