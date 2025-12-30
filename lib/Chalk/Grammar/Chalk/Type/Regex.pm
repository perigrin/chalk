# ABOUTME: Regex type representing compiled regular expressions in the Chalk type system
# ABOUTME: Implements Regex <: Ref <: Any subtyping chain

use 5.42.0;
use experimental qw(class keyword_any);

class Chalk::Grammar::Chalk::Type::Regex :isa(Chalk::Grammar::Chalk::Type) {
    # Regex represents compiled regular expressions (qr//)
    # Regex <: Ref <: Any
    # Note: Regex is a reference type since qr// creates a Regexp object

    method is_subtype_of($other) {
        # Regex <: Regex (reflexive)
        # Regex <: Ref
        # Regex <: Any

        return any { $other isa $_ } (
            'Chalk::Grammar::Chalk::Type::Regex',
            'Chalk::Grammar::Chalk::Type::Ref',
            'Chalk::Grammar::Chalk::Type::Any',
        );
    }

    method round_trip_preserves($value) {
        # Regex values preserve through compilation
        return defined($value);
    }

    method satisfies_contract($value) {
        # Regex values should be compilable patterns
        return defined($value);
    }
}

1;
