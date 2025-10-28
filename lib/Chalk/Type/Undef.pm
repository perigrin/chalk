# ABOUTME: Undef type representing undefined values in the Chalk type system
# ABOUTME: Implements Undef <: Scalar <: Any subtyping chain

use 5.042;
use experimental qw(class);

class Chalk::Type::Undef :isa(Chalk::Type) {
    # Undef represents undefined values
    # Undef <: Scalar <: Any

    method is_subtype_of($other) {
        # Undef <: Undef (reflexive)
        # Undef <: Scalar
        # Undef <: Any
        return ref($other) eq 'Chalk::Type::Undef' ||
               ref($other) eq 'Chalk::Type::Scalar' ||
               ref($other) eq 'Chalk::Type::Any';
    }

    method round_trip_preserves($value) {
        # Only undef is valid for Undef type
        return !defined($value);
    }

    method satisfies_contract($value) {
        # Undef must be undefined
        return !defined($value);
    }
}

1;
