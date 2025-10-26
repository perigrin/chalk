# ABOUTME: Num type representing numeric values in the Chalk type system
# ABOUTME: Implements Num <: Str <: Scalar <: Any chain (numbers round-trip through strings)

use 5.042;
use experimental qw(class);

class Chalk::Type::Num :isa(Chalk::Type) {
    # Num represents numeric values
    # Num <: Str <: Scalar <: Any
    # Num <: Str because numbers round-trip through string conversion without loss

    method is_subtype_of($other) {
        # Num <: Num (reflexive)
        # Num <: Str (round-trip preservation)
        # Num <: Scalar
        # Num <: Any
        return ref($other) eq 'Chalk::Type::Num' ||
               ref($other) eq 'Chalk::Type::Str' ||
               ref($other) eq 'Chalk::Type::Scalar' ||
               ref($other) eq 'Chalk::Type::Any';
    }
}

1;
