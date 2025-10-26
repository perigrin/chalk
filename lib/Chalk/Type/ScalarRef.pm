# ABOUTME: ScalarRef type representing scalar references in the Chalk type system
# ABOUTME: Implements ScalarRef <: Ref <: Scalar <: Any subtyping chain

use 5.042;
use experimental qw(class);

class Chalk::Type::ScalarRef :isa(Chalk::Type) {
    # ScalarRef represents scalar references
    # ScalarRef <: Ref <: Scalar <: Any

    method is_subtype_of($other) {
        # ScalarRef <: ScalarRef (reflexive)
        # ScalarRef <: Ref
        # ScalarRef <: Scalar (transitive)
        # ScalarRef <: Any (transitive)
        return ref($other) eq 'Chalk::Type::ScalarRef' ||
               ref($other) eq 'Chalk::Type::Ref' ||
               ref($other) eq 'Chalk::Type::Scalar' ||
               ref($other) eq 'Chalk::Type::Any';
    }
}

1;
