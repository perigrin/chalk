# ABOUTME: Hash type representing hash values with parameterized value type
# ABOUTME: Implements Hash <: List <: Any subtyping chain with value_type parameter

use 5.042;
use experimental qw(class);

class Chalk::Grammar::Chalk::Type::Hash :isa(Chalk::Grammar::Chalk::Type) {
    # Hash represents hash values
    # Hash <: List <: Any
    # Parameterized by value_type

    field $value_type :param :reader;

    method is_subtype_of($other) {
        # Hash <: Hash (reflexive)
        # Hash <: List
        # Hash <: Any (transitive)
        return ref($other) eq 'Chalk::Grammar::Chalk::Type::Hash' ||
               ref($other) eq 'Chalk::Grammar::Chalk::Type::List' ||
               ref($other) eq 'Chalk::Grammar::Chalk::Type::Any';
    }
}

1;
