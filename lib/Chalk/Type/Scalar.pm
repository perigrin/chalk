# ABOUTME: Base scalar type in the Chalk type lattice - parent of all scalar types
# ABOUTME: Implements Scalar <: Any subtyping relationship

use 5.042;
use experimental qw(class);

class Chalk::Type::Scalar :isa(Chalk::Type) {
    # Scalar is the base type for all scalar values
    # Scalar <: Any

    method is_subtype_of($other) {
        # Scalar <: Scalar (reflexive)
        # Scalar <: Any
        return ref($other) eq 'Chalk::Type::Scalar' ||
               ref($other) eq 'Chalk::Type::Any';
    }
}

1;
