# ABOUTME: ArrayRef type representing array references in the Chalk type system
# ABOUTME: Implements ArrayRef <: Ref <: Scalar <: Any subtyping chain

use 5.042;
use experimental qw(class);

class Chalk::Grammar::Chalk::Type::ArrayRef :isa(Chalk::Grammar::Chalk::Type) {
    # ArrayRef represents array references
    # ArrayRef <: Ref <: Scalar <: Any

    method is_subtype_of($other) {
        # ArrayRef <: ArrayRef (reflexive)
        # ArrayRef <: Ref
        # ArrayRef <: Scalar (transitive)
        # ArrayRef <: Any (transitive)
        return ref($other) eq 'Chalk::Grammar::Chalk::Type::ArrayRef' ||
               ref($other) eq 'Chalk::Grammar::Chalk::Type::Ref' ||
               ref($other) eq 'Chalk::Grammar::Chalk::Type::Scalar' ||
               ref($other) eq 'Chalk::Grammar::Chalk::Type::Any';
    }
}

1;
