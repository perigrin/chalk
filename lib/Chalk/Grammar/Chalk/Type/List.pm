# ABOUTME: List type representing ephemeral list values in the Chalk type system
# ABOUTME: Implements List <: Any subtyping chain, parent of Array and Hash types

use 5.042;
use experimental qw(class keyword_any);
use Chalk::Grammar::Chalk::Type::Any;
use Chalk::Grammar::Chalk::Type::Array;
use Chalk::Grammar::Chalk::Type::Hash;
use Chalk::Grammar::Chalk::Type::Exception;

class Chalk::Grammar::Chalk::Type::List :isa(Chalk::Grammar::Chalk::Type) {
    # List represents ephemeral list values
    # Exists only during list-context evaluation
    # List <: Any
    # Array and Hash are subtypes of List

    field $element_type :param = undef;  # Optional element type parameter

    method is_subtype_of($other) {
        # List <: List (reflexive)
        # List <: Any
        return $other isa Chalk::Grammar::Chalk::Type::List ||
               $other isa Chalk::Grammar::Chalk::Type::Any;
    }

    method convert_to_target($target_sigil) {
        # Convert ephemeral List to concrete container type based on sigil
        # This implements the ephemeral type conversion described in Issue #74 Phase 3

        if ($target_sigil eq '@') {
            # List to Array conversion
            my $elem_type = $element_type // Chalk::Grammar::Chalk::Type::Any->new();
            return Chalk::Grammar::Chalk::Type::Array->new(element_type => $elem_type);
        }

        if ($target_sigil eq '%') {
            # List to Hash conversion
            my $val_type = $element_type // Chalk::Grammar::Chalk::Type::Any->new();
            return Chalk::Grammar::Chalk::Type::Hash->new(value_type => $val_type);
        }

        # List cannot be assigned to scalar variable
        my $exception = Chalk::Grammar::Chalk::Type::Exception->invalid_list_assignment_error($target_sigil);
        $exception->throw();
    }
}
