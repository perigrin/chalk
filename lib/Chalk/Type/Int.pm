# ABOUTME: Int type representing integer values in the Chalk type system
# ABOUTME: Implements Int <: Num <: Str <: Scalar <: Any subtyping chain

use 5.042;
use experimental qw(class);

class Chalk::Type::Int :isa(Chalk::Type) {
    # Int represents integer values
    # Int <: Num <: Str <: Scalar <: Any

    method is_subtype_of($other) {
        # Int <: Int (reflexive)
        # Int <: Num
        # Int <: Str (transitive)
        # Int <: Scalar (transitive)
        # Int <: Any (transitive)
        return ref($other) eq 'Chalk::Type::Int' ||
               ref($other) eq 'Chalk::Type::Num' ||
               ref($other) eq 'Chalk::Type::Str' ||
               ref($other) eq 'Chalk::Type::Scalar' ||
               ref($other) eq 'Chalk::Type::Any';
    }
}

1;
