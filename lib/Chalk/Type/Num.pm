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

    method round_trip_preserves($value) {
        # Num to Str to Num should be observationally equivalent
        # Valid numbers round-trip through string conversion
        return defined($value) && $value =~ qr/^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$/;
    }

    method satisfies_contract($value) {
        # Numbers must satisfy reflexivity: value equals itself
        # This excludes NaN (NaN not-equals NaN)
        return defined($value) && $value == $value;
    }
}

1;
