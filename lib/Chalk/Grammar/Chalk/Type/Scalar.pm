# ABOUTME: Base scalar type in the Chalk type lattice - parent of all scalar types
# ABOUTME: Implements Scalar <: Any subtyping relationship

use 5.042;
use experimental qw(class keyword_any);

class Chalk::Grammar::Chalk::Type::Scalar :isa(Chalk::Grammar::Chalk::Type) {
    # Scalar is the base type for all scalar values
    # Scalar <: Any

    method is_subtype_of($other) {
        # Scalar <: Scalar (reflexive)
        # Scalar <: Any
        
return any { $other isa $_ } (
            'Chalk::Grammar::Chalk::Type::Scalar',
            'Chalk::Grammar::Chalk::Type::Any',
            
        );
    }
}

1;
