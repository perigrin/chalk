# ABOUTME: Array type representing array values with parameterized element type
# ABOUTME: Implements Array <: List <: Any subtyping chain with element_type parameter

use 5.042;
use experimental qw(class);

class Chalk::Type::Array :isa(Chalk::Type) {
    # Array represents array values
    # Array <: List <: Any
    # Parameterized by element_type

    field $element_type :param :reader;

    method is_subtype_of($other) {
        # Array <: Array (reflexive)
        # Array <: List
        # Array <: Any (transitive)
        return ref($other) eq 'Chalk::Type::Array' ||
               ref($other) eq 'Chalk::Type::List' ||
               ref($other) eq 'Chalk::Type::Any';
    }
}

1;
