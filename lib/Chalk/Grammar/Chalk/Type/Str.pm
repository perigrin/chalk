# ABOUTME: Str type representing string values in the Chalk type system
# ABOUTME: Implements Str <: Scalar <: Any subtyping chain

use 5.042;
use experimental qw(class keyword_any);

class Chalk::Grammar::Chalk::Type::Str :isa(Chalk::Grammar::Chalk::Type) {
    # Str represents string values
    # Str <: Scalar <: Any
    # Note: Num <: Str because numbers round-trip through string conversion

    method is_subtype_of($other) {
        # Str <: Str (reflexive)
        # Str <: Scalar
        # Str <: Any
        
return any { $other isa $_ } (
            'Chalk::Grammar::Chalk::Type::Str',
            'Chalk::Grammar::Chalk::Type::Scalar',
            'Chalk::Grammar::Chalk::Type::Any',
            
        );
    }

    method round_trip_preserves($value) {
        # All strings trivially round-trip
        return defined($value);
    }

    method satisfies_contract($value) {
        # Strings have no special contracts
        return defined($value);
    }
}

1;
