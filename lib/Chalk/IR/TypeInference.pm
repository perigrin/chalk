# ABOUTME: Type inference for IR nodes in dynamic language context
# ABOUTME: Provides static type analysis without external dependencies
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::TypeInference {
    field $context :param :reader = undef;
    field $graph   :param :reader = undef;

    # Infer the type of a value produced by an IR node
    # Returns type string: 'Int', 'Str', 'Array', 'Hash', 'Object:ClassName', 'Bool', 'Num', or undef
    method infer_type($node) {
        return undef unless defined $node;
        return undef unless ref($node);

        my $op = $node->op;

        # Constants have explicit types
        if ($op eq 'Constant') {
            my $type = $node->attributes->{type};
            return $type if defined $type;
            return 'Int';  # Default for constants
        }

        # Collection types
        return 'Array' if $op eq 'ArrayValue';
        return 'Hash' if $op eq 'HashValue';

        # Object construction
        if ($op eq 'New') {
            my $class = $node->attributes->{class};
            return "Object:$class" if defined $class;
        }

        # Arithmetic operations return numbers
        return 'Num' if $op =~ /^(Add|Subtract|Multiply|Divide|Negate)$/;

        # Comparison operations return boolean
        return 'Bool' if $op =~ /^(GT|LT|EQ|NE|GE|LE)$/;

        # Logical operations
        return 'Bool' if $op =~ /^(And|Or|Not)$/;

        # String operations
        return 'Str' if $op eq 'Concat';

        # Array/Hash access - type depends on what's stored
        # We'd need to trace through context to know for sure
        if ($op =~ /^(ArrayGet|HashGet)$/) {
            # Could be anything - would need context analysis
            return undef;
        }

        # Variable reads - look up in context if possible
        if ($op eq 'VariableRead') {
            return $self->_infer_type_from_variable_read($node);
        }

        # Phi nodes - would need to check all inputs (pick first for now)
        if ($op eq 'Phi') {
            return $self->_infer_type_from_phi($node);
        }

        # Unknown type
        return undef;
    }

    # Infer the class name of an object node
    # Returns class name string or undef
    method infer_class($node) {
        return undef unless defined $node;
        return undef unless ref($node);

        # Direct object construction
        if ($node->op eq 'New') {
            return $node->attributes->{class};
        }

        # Try to infer from type
        my $type = $self->infer_type($node);
        if (defined $type && $type =~ /^Object:(.+)$/) {
            return $1;
        }

        # Could trace through variable assignments, but that's complex
        # For now, return undef if we can't determine statically
        return undef;
    }

    # Helper: Infer type from variable read node
    method _infer_type_from_variable_read($node) {
        return undef unless defined $context;

        my $var_label = $node->attributes->{var_label};
        return undef unless defined $var_label;

        my $var_node = $context->($var_label);
        return undef unless defined $var_node;
        return undef if $var_node == $node;  # Avoid infinite recursion

        # Recursively infer type from the stored node
        return $self->infer_type($var_node);
    }

    # Helper: Infer type from phi node
    method _infer_type_from_phi($node) {
        return undef unless defined $graph;

        my $inputs = $node->inputs;
        return undef unless $inputs && scalar(@$inputs) > 1;

        # First input is control, second is first value
        my $first_val_id = $inputs->[1];
        return undef unless defined $first_val_id;

        my $first_node = $graph->get_node($first_val_id);
        return $self->infer_type($first_node);
    }
}

1;
