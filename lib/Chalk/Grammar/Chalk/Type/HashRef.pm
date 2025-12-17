# ABOUTME: HashRef type representing hash references in the Chalk type system
# ABOUTME: Implements HashRef <: Ref <: Scalar <: Any subtyping chain

use 5.42.0;
use experimental qw(class keyword_any);

class Chalk::Grammar::Chalk::Type::HashRef :isa(Chalk::Grammar::Chalk::Type) {
    # HashRef represents hash references
    # HashRef <: Ref <: Scalar <: Any

    method is_subtype_of($other) {
        # HashRef <: HashRef (reflexive)
        # HashRef <: Ref
        # HashRef <: Scalar (transitive)
        # HashRef <: Any (transitive)
        
return any { $other isa $_ } (
            'Chalk::Grammar::Chalk::Type::HashRef',
            'Chalk::Grammar::Chalk::Type::Ref',
            'Chalk::Grammar::Chalk::Type::Scalar',
            'Chalk::Grammar::Chalk::Type::Any',
            
        );
    }
}

1;
