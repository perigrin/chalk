# ABOUTME: ArrayRef type representing array references in the Chalk type system
# ABOUTME: Implements ArrayRef <: Ref <: Scalar <: Any subtyping chain

use 5.042;
use experimental qw(class keyword_any);

class Chalk::Grammar::Chalk::Type::ArrayRef :isa(Chalk::Grammar::Chalk::Type) {
    # ArrayRef represents array references
    # ArrayRef <: Ref <: Scalar <: Any

    method is_subtype_of($other) {
        # ArrayRef <: ArrayRef (reflexive)
        # ArrayRef <: Ref
        # ArrayRef <: Scalar (transitive)
        # ArrayRef <: Any (transitive)
        
return any { $other isa $_ } (
            'Chalk::Grammar::Chalk::Type::ArrayRef',
            'Chalk::Grammar::Chalk::Type::Ref',
            'Chalk::Grammar::Chalk::Type::Scalar',
            'Chalk::Grammar::Chalk::Type::Any',
            
        );
    }
}

1;
