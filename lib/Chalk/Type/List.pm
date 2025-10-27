# ABOUTME: List type representing ephemeral list values in the Chalk type system
# ABOUTME: Implements List <: Any subtyping chain, parent of Array and Hash types

use 5.042;
use experimental qw(class);
use Chalk::Type::Array;
use Chalk::Type::Hash;
use Chalk::Type::Any;
use Chalk::Type::Exception;

class Chalk::Type::List :isa(Chalk::Type) {
    # List represents ephemeral list values
    # Exists only during list-context evaluation
    # List <: Any
    # Array and Hash are subtypes of List

    field $element_type :param = undef;  # Optional element type parameter

    method is_subtype_of($other) {
        # List <: List (reflexive)
        # List <: Any
        return ref($other) eq 'Chalk::Type::List' ||
               ref($other) eq 'Chalk::Type::Any';
    }

    method convert_to_target($target_sigil) {
        # Convert ephemeral List to concrete container type based on sigil
        # This implements the ephemeral type conversion described in Issue #74 Phase 3

        if ($target_sigil eq '@') {
            # List to Array conversion
            my $elem_type = $element_type // Chalk::Type::Any->new();
            return Chalk::Type::Array->new(element_type => $elem_type);
        }

        if ($target_sigil eq '%') {
            # List to Hash conversion
            my $val_type = $element_type // Chalk::Type::Any->new();
            return Chalk::Type::Hash->new(value_type => $val_type);
        }

        # List cannot be assigned to scalar variable
        Chalk::Type::Exception::invalid_list_assignment_error($target_sigil)->throw();
    }
}

1;
