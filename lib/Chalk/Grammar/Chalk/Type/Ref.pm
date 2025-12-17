# ABOUTME: Ref type representing reference values in the Chalk type system
# ABOUTME: Implements Ref <: Scalar <: Any subtyping chain, parent of all reference types

use 5.42.0;
use experimental qw(class keyword_any);

class Chalk::Grammar::Chalk::Type::Ref :isa(Chalk::Grammar::Chalk::Type) {
    # Ref represents all reference values
    # Ref <: Scalar <: Any
    # All specific reference types (Object, ScalarRef, etc.) are subtypes of Ref

    method is_subtype_of($other) {
        # Ref <: Ref (reflexive)
        # Ref <: Scalar
        # Ref <: Any
        
return any { $other isa $_ } (
            'Chalk::Grammar::Chalk::Type::Ref',
            'Chalk::Grammar::Chalk::Type::Scalar',
            'Chalk::Grammar::Chalk::Type::Any',
            
        );
    }
}

1;
