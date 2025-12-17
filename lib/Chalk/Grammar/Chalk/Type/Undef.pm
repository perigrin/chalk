# ABOUTME: Undef type representing undefined values in the Chalk type system
# ABOUTME: Implements Undef <: Scalar <: Any subtyping chain

use 5.42.0;
use experimental qw(class keyword_any);

class Chalk::Grammar::Chalk::Type::Undef :isa(Chalk::Grammar::Chalk::Type) {
    # Undef represents undefined values
    # Undef <: Scalar <: Any

    method is_subtype_of($other) {
        # Undef <: Undef (reflexive)
        # Undef <: Scalar
        # Undef <: Any
        
return any { $other isa $_ } (
            'Chalk::Grammar::Chalk::Type::Undef',
            'Chalk::Grammar::Chalk::Type::Scalar',
            'Chalk::Grammar::Chalk::Type::Any',
            
        );
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
