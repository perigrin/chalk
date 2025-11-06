# ABOUTME: Type inference for IR nodes using grammar-specific type lattice
# ABOUTME: Provides static type analysis by delegating to language-specific TypeLattice
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::TypeInference {
    field $context      :param :reader = undef;
    field $graph        :param :reader = undef;
    field $type_lattice :param :reader;  # Grammar-specific type system

    # Maximum recursion depth to prevent stack overflow on circular dependencies
    use constant MAX_TYPE_RECURSION_DEPTH => 50;

    # Infer the type of a value produced by an IR node
    # Returns Chalk::Grammar::Chalk::Type::* object or undef
    method infer_type($node, $depth = 0) {
        return undef unless defined $node;
        return undef unless ref($node);

        # Prevent infinite recursion on circular dependencies
        if ($depth > MAX_TYPE_RECURSION_DEPTH) {
            warn "Type inference exceeded maximum recursion depth ($depth) - possible circular dependency";
            return undef;
        }

        my $op = $node->op;

        # Delegate to type lattice for operation-specific inference
        my $type = $type_lattice->infer_type_from_operation($op, $node);
        return $type if defined $type;

        # Special cases that need context/graph analysis

        # Variable reads - look up in context if possible
        if ($op eq 'VariableRead') {
            return $self->_infer_type_from_variable_read($node, $depth);
        }

        # Phi nodes - check all inputs (pick first for now)
        if ($op eq 'Phi') {
            return $self->_infer_type_from_phi($node, $depth);
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

        # Try to infer from type - check if it's an Object type
        my $type = $self->infer_type($node);
        if (defined $type) {
            # Check if this is an Object type (Chalk::Grammar::Chalk::Type::Object)
            my $type_name = $type_lattice->type_name($type);
            if ($type_name eq 'Object') {
                # Try to get class from node attributes
                return $node->attributes->{class} if defined $node->attributes;
            }
        }

        # Could trace through variable assignments, but that's complex
        # For now, return undef if we can't determine statically
        return undef;
    }

    # Helper: Infer type from variable read node
    method _infer_type_from_variable_read($node, $depth = 0) {
        return undef unless defined $context;

        # Prevent infinite recursion
        return undef if $depth > MAX_TYPE_RECURSION_DEPTH;

        my $var_label = $node->attributes->{var_label};
        return undef unless defined $var_label;

        my $var_node = $context->($var_label);
        return undef unless defined $var_node;
        return undef if $var_node == $node;  # Avoid direct self-reference

        # Recursively infer type from the stored node
        return $self->infer_type($var_node, $depth + 1);
    }

    # Helper: Infer type from phi node
    method _infer_type_from_phi($node, $depth = 0) {
        return undef unless defined $graph;

        # Prevent infinite recursion
        return undef if $depth > MAX_TYPE_RECURSION_DEPTH;

        my $inputs = $node->inputs;
        return undef unless $inputs && scalar(@$inputs) > 1;

        # First input is control, second is first value
        my $first_val_id = $inputs->[1];
        return undef unless defined $first_val_id;

        my $first_node = $graph->get_node($first_val_id);
        return $self->infer_type($first_node, $depth + 1);
    }
}

1;
