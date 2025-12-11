# ABOUTME: Int type representing integer values in the Chalk type system
# ABOUTME: Implements Int <: Num <: Str <: Scalar <: Any subtyping chain

use 5.042;
use experimental qw(class keyword_any);

class Chalk::Grammar::Chalk::Type::Int :isa(Chalk::Grammar::Chalk::Type) {
    # Int represents integer values
    # Int <: Num <: Str <: Scalar <: Any

    method is_subtype_of($other) {
        # Int <: Int (reflexive)
        # Int <: Num
        # Int <: Str (transitive)
        # Int <: Scalar (transitive)
        # Int <: Any (transitive)
        
return any { $other isa $_ } (
            'Chalk::Grammar::Chalk::Type::Int',
            'Chalk::Grammar::Chalk::Type::Num',
            'Chalk::Grammar::Chalk::Type::Str',
            'Chalk::Grammar::Chalk::Type::Scalar',
            'Chalk::Grammar::Chalk::Type::Any',
            
        );
    }

    method round_trip_preserves($value) {
        # Int to Str to Int must preserve value
        # Must be a whole number (no fractional part)
        return defined($value) && $value =~ qr/^[+-]?\d+$/ && int($value) == $value;
    }

    method satisfies_contract($value) {
        # Integers must satisfy reflexivity and be whole numbers
        return defined($value) && $value == $value && int($value) == $value;
    }
}

1;
