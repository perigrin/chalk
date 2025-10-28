# ABOUTME: Code type representing code/subroutine values in the Chalk type system
# ABOUTME: Implements Code <: Any subtyping chain (not a Scalar subtype)

use 5.042;
use experimental qw(class);

class Chalk::Type::Code :isa(Chalk::Type) {
    # Code represents code/subroutine values
    # Code <: Any (direct subtype, not through Scalar)
    # Note: Code is NOT a subtype of Scalar

    method is_subtype_of($other) {
        # Code <: Code (reflexive)
        # Code <: Any
        return ref($other) eq 'Chalk::Type::Code' ||
               ref($other) eq 'Chalk::Type::Any';
    }
}

1;
