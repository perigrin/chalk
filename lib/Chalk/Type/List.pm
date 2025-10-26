# ABOUTME: List type representing ephemeral list values in the Chalk type system
# ABOUTME: Implements List <: Any subtyping chain, parent of Array and Hash types

use 5.042;
use experimental qw(class);

class Chalk::Type::List :isa(Chalk::Type) {
    # List represents ephemeral list values
    # Exists only during list-context evaluation
    # List <: Any
    # Array and Hash are subtypes of List

    method is_subtype_of($other) {
        # List <: List (reflexive)
        # List <: Any
        return ref($other) eq 'Chalk::Type::List' ||
               ref($other) eq 'Chalk::Type::Any';
    }
}

1;
