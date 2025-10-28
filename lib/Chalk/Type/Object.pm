# ABOUTME: Object type representing blessed references in the Chalk type system
# ABOUTME: Implements Object <: Ref <: Scalar <: Any subtyping chain

use 5.042;
use experimental qw(class);

class Chalk::Type::Object :isa(Chalk::Type) {
    # Object represents blessed references
    # Object <: Ref <: Scalar <: Any

    method is_subtype_of($other) {
        # Object <: Object (reflexive)
        # Object <: Ref
        # Object <: Scalar (transitive)
        # Object <: Any (transitive)
        return ref($other) eq 'Chalk::Type::Object' ||
               ref($other) eq 'Chalk::Type::Ref' ||
               ref($other) eq 'Chalk::Type::Scalar' ||
               ref($other) eq 'Chalk::Type::Any';
    }
}

1;
