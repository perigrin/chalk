# ABOUTME: Cast node for type upcasting (type refinement via join operation)
# ABOUTME: Used after guard tests to lift/refine input type, can also be used for type assertions
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Cast :isa(Chalk::IR::Node::Base) {

    # Target type to cast to
    field $target_type :param :reader;

    # Control flow dependency (nullable for type assertions)
    field $ctrl :param :reader = undef;

    # Input value being cast
    field $input :param :reader;

    method op() { 'Cast' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Cast',
            inputs => $self->inputs,
            attributes => {
                target_type => $target_type,
            },
        };
    }

    # Compute output type by joining input type with target type
    # This produces the most precise type that satisfies both constraints
    method compute() {
        return Chalk::IR::Type::Top->top() unless $input;

        my $input_type = $input->compute();

        # Join the input type with the target type
        return $input_type->join($target_type);
    }

    # Peephole optimization: eliminate redundant casts
    # If the input already satisfies the target type, return the input directly
    method peephole($graph = undef) {
        return $self unless $graph;
        return $self unless $input;

        my $input_type = $input->compute();

        # Check if input type is already a subtype of (or equal to) target type
        # This uses the isa() method if available, otherwise checks type equality
        if ($input_type->can('isa') && $input_type->isa($target_type)) {
            # Input already satisfies target type - cast is redundant
            return $input;
        }

        # For types without isa(), check if they're the same type
        # or if the input is more specific (constant vs TOP)
        if ($self->_type_satisfies($input_type, $target_type)) {
            return $input;
        }

        return $self;
    }

    # Helper method to check if input_type satisfies target_type
    method _type_satisfies($input_type, $target_type) {
        # Same type reference = satisfies
        return 1 if $input_type == $target_type;

        # If target is TOP, everything satisfies it
        return 1 if $target_type->can('is_top') && $target_type->is_top;

        # Handle MemoryPointer type satisfaction
        if ($input_type isa Chalk::IR::Type::MemoryPointer &&
            $target_type isa Chalk::IR::Type::MemoryPointer) {

            # Check struct names match (or are both undefined)
            my $input_struct = $input_type->struct_name;
            my $target_struct = $target_type->struct_name;

            unless ((!defined($input_struct) && !defined($target_struct)) ||
                    $input_struct eq $target_struct) {
                return 0;  # Struct types don't match
            }

            # Non-null pointer satisfies nullable target (widening)
            # Non-null pointer satisfies non-null target (same)
            # Nullable pointer does NOT satisfy non-null target (narrowing - unsafe)
            if ($input_type->nullable && !$target_type->nullable) {
                return 0;  # Cannot narrow nullable to non-null without check
            }

            return 1;  # Types are compatible
        }

        # If both are same class and input is constant while target is TOP,
        # the constant satisfies the TOP type
        if ($input_type isa $target_type) {
            if ($input_type->can('is_constant') && $input_type->is_constant &&
                $target_type->can('is_top') && $target_type->is_top) {
                return 1;
            }
            # Same type, same value = satisfies
            if ($input_type->can('is_constant') && $target_type->can('is_constant') &&
                $input_type->is_constant && $target_type->is_constant) {
                return $input_type->value == $target_type->value;
            }
        }

        return 0;
    }
}

1;
