# ABOUTME: Ref type representing reference values in the Chalk type system
# ABOUTME: Implements Ref <: Scalar <: Any subtyping chain, parent of all reference types

use 5.042;
use experimental qw(class);

class Chalk::Grammar::Chalk::Type::Ref :isa(Chalk::Grammar::Chalk::Type) {
    # Ref represents all reference values
    # Ref <: Scalar <: Any
    # All specific reference types (Object, ScalarRef, etc.) are subtypes of Ref

    method is_subtype_of($other) {
        # Ref <: Ref (reflexive)
        # Ref <: Scalar
        # Ref <: Any
        return ref($other) eq 'Chalk::Grammar::Chalk::Type::Ref' ||
               ref($other) eq 'Chalk::Grammar::Chalk::Type::Scalar' ||
               ref($other) eq 'Chalk::Grammar::Chalk::Type::Any';
    }
}

1;
