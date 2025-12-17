# ABOUTME: Object type representing blessed references in the Chalk type system
# ABOUTME: Implements Object <: Ref <: Scalar <: Any subtyping chain

use 5.42.0;
use experimental qw(class keyword_any);

class Chalk::Grammar::Chalk::Type::Object :isa(Chalk::Grammar::Chalk::Type) {
    # Object represents blessed references
    # Object <: Ref <: Scalar <: Any

    method is_subtype_of($other) {
        # Object <: Object (reflexive)
        # Object <: Ref
        # Object <: Scalar (transitive)
        # Object <: Any (transitive)
        
return any { $other isa $_ } (
            'Chalk::Grammar::Chalk::Type::Object',
            'Chalk::Grammar::Chalk::Type::Ref',
            'Chalk::Grammar::Chalk::Type::Scalar',
            'Chalk::Grammar::Chalk::Type::Any',
            
        );
    }
}

1;
