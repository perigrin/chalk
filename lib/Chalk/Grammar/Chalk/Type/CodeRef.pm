# ABOUTME: CodeRef type representing code references in the Chalk type system
# ABOUTME: Implements CodeRef <: Ref <: Scalar <: Any subtyping chain

use 5.42.0;
use experimental qw(class keyword_any);

class Chalk::Grammar::Chalk::Type::CodeRef :isa(Chalk::Grammar::Chalk::Type) {
    # CodeRef represents code references
    # CodeRef <: Ref <: Scalar <: Any

    method is_subtype_of($other) {
        # CodeRef <: CodeRef (reflexive)
        # CodeRef <: Ref
        # CodeRef <: Scalar (transitive)
        # CodeRef <: Any (transitive)
        
return any { $other isa $_ } (
            'Chalk::Grammar::Chalk::Type::CodeRef',
            'Chalk::Grammar::Chalk::Type::Ref',
            'Chalk::Grammar::Chalk::Type::Scalar',
            'Chalk::Grammar::Chalk::Type::Any',
            
        );
    }
}

1;
