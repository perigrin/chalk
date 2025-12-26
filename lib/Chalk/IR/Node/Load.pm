# ABOUTME: Load node for reading variable values while preserving variable identity
# ABOUTME: Wraps bound value with variable name for use in both lvalue and rvalue contexts
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Load :isa(Chalk::IR::Node::Base) {
    field $name :param :reader;    # Variable name with sigil (e.g., '$x')
    field $value :param :reader;   # The bound value node (e.g., Constant)

    method op() { 'Load' }

    method inputs() {
        return [] unless defined $value && ref($value) && $value->can('id');
        return [$value->id];
    }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Load',
            inputs => $self->inputs,
            attributes => {
                name => $name,
            },
        };
    }

    # Peephole optimization: Load's type is the value's type
    method compute() {
        return $value->compute if $value && $value->can('compute');
        return $value->compute_type if $value && $value->can('compute_type');
        return undef;
    }

    # Peephole: Load of a constant can be replaced by the constant
    method idealize() {
        # If the value is a Constant, we can use it directly
        return $value if $value && $value->can('op') && $value->op eq 'Constant';
        return undef;  # No optimization
    }

    method execute($context) {
        # Execute the value node to get the actual value
        return $value->execute($context) if $value && $value->can('execute');
        return undef;
    }
}

1;
