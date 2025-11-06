# ABOUTME: Object type representing blessed references in the Chalk type system
# ABOUTME: Implements Object <: Ref <: Scalar <: Any subtyping chain

use 5.042;
use experimental qw(class);

class Chalk::Grammar::Chalk::Type::Object :isa(Chalk::Grammar::Chalk::Type) {
    # Object represents blessed references
    # Object <: Ref <: Scalar <: Any

    method is_subtype_of($other) {
        # Object <: Object (reflexive)
        # Object <: Ref
        # Object <: Scalar (transitive)
        # Object <: Any (transitive)
        return ref($other) eq 'Chalk::Grammar::Chalk::Type::Object' ||
               ref($other) eq 'Chalk::Grammar::Chalk::Type::Ref' ||
               ref($other) eq 'Chalk::Grammar::Chalk::Type::Scalar' ||
               ref($other) eq 'Chalk::Grammar::Chalk::Type::Any';
    }
}

1;
