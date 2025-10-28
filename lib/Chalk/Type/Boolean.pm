# ABOUTME: Boolean type representing all truthy and falsy values in Chalk
# ABOUTME: Implements Boolean <: Scalar <: Any subtyping chain

use 5.042;
use experimental qw(class);

class Chalk::Type::Boolean :isa(Chalk::Type) {
    # Boolean represents all truthy and falsy values
    # Boolean <: Scalar <: Any

    method is_subtype_of($other) {
        # Boolean <: Boolean (reflexive)
        # Boolean <: Scalar
        # Boolean <: Any
        return ref($other) eq 'Chalk::Type::Boolean' ||
               ref($other) eq 'Chalk::Type::Scalar' ||
               ref($other) eq 'Chalk::Type::Any';
    }

    method round_trip_preserves($value) {
        # All values (truthy or falsy) round-trip through boolean context
        return 1;  # Boolean type contains all truthy/falsy values
    }

    method satisfies_contract($value) {
        # Boolean values must be evaluable in boolean context
        return 1;  # All Perl values have boolean context
    }
}

1;
