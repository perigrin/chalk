# ABOUTME: Str type representing string values in the Chalk type system
# ABOUTME: Implements Str <: Scalar <: Any subtyping chain

use 5.042;
use experimental qw(class);

class Chalk::Type::Str :isa(Chalk::Type) {
    # Str represents string values
    # Str <: Scalar <: Any
    # Note: Num <: Str because numbers round-trip through string conversion

    method is_subtype_of($other) {
        # Str <: Str (reflexive)
        # Str <: Scalar
        # Str <: Any
        return ref($other) eq 'Chalk::Type::Str' ||
               ref($other) eq 'Chalk::Type::Scalar' ||
               ref($other) eq 'Chalk::Type::Any';
    }
}

1;
