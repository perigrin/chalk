# ABOUTME: CodeRef type representing code references in the Chalk type system
# ABOUTME: Implements CodeRef <: Ref <: Scalar <: Any subtyping chain

use 5.042;
use experimental qw(class);

class Chalk::Type::CodeRef :isa(Chalk::Type) {
    # CodeRef represents code references
    # CodeRef <: Ref <: Scalar <: Any

    method is_subtype_of($other) {
        # CodeRef <: CodeRef (reflexive)
        # CodeRef <: Ref
        # CodeRef <: Scalar (transitive)
        # CodeRef <: Any (transitive)
        return ref($other) eq 'Chalk::Type::CodeRef' ||
               ref($other) eq 'Chalk::Type::Ref' ||
               ref($other) eq 'Chalk::Type::Scalar' ||
               ref($other) eq 'Chalk::Type::Any';
    }
}

1;
