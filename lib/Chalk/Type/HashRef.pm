# ABOUTME: HashRef type representing hash references in the Chalk type system
# ABOUTME: Implements HashRef <: Ref <: Scalar <: Any subtyping chain

use 5.042;
use experimental qw(class);

class Chalk::Type::HashRef :isa(Chalk::Type) {
    # HashRef represents hash references
    # HashRef <: Ref <: Scalar <: Any

    method is_subtype_of($other) {
        # HashRef <: HashRef (reflexive)
        # HashRef <: Ref
        # HashRef <: Scalar (transitive)
        # HashRef <: Any (transitive)
        return ref($other) eq 'Chalk::Type::HashRef' ||
               ref($other) eq 'Chalk::Type::Ref' ||
               ref($other) eq 'Chalk::Type::Scalar' ||
               ref($other) eq 'Chalk::Type::Any';
    }
}

1;
