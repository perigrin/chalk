# ABOUTME: Array type representing array values with parameterized element type
# ABOUTME: Implements Array <: List <: Any subtyping chain with element_type parameter

use 5.42.0;
use experimental qw(class keyword_any);

class Chalk::Grammar::Chalk::Type::Array :isa(Chalk::Grammar::Chalk::Type) {
    # Array represents array values
    # Array <: List <: Any
    # Parameterized by element_type

    field $element_type :param :reader;

    method is_subtype_of($other) {
        # Array <: Array (reflexive)
        # Array <: List
        # Array <: Any (transitive)
        
return any { $other isa $_ } (
            'Chalk::Grammar::Chalk::Type::Array',
            'Chalk::Grammar::Chalk::Type::List',
            'Chalk::Grammar::Chalk::Type::Any',
            
        );
    }

    method meet($other) {
        # Handle boundary cases
        return $other if $other->is_bottom();
        return $self if $other->is_top();

        # Array meet Array: covariant element types
        if (            $other isa Chalk::Grammar::Chalk::Type::Array) {
            my $elem_meet = $element_type->meet($other->element_type);
            return Chalk::Grammar::Chalk::Type::Array->new(element_type => $elem_meet);
        }

        # Array meet non-Array: incompatible types return None
        return Chalk::Grammar::Chalk::Type::None->new();
    }

    method join($other) {
        # Handle boundary cases
        return $self if $other->is_bottom();
        return $other if $other->is_top();

        # Array join Array: covariant element types
        if (            $other isa Chalk::Grammar::Chalk::Type::Array) {
            my $elem_join = $element_type->join($other->element_type);
            return Chalk::Grammar::Chalk::Type::Array->new(element_type => $elem_join);
        }

        # Array join non-Array: find common supertype
        # Both Array and Hash are under List
        my $list = Chalk::Grammar::Chalk::Type::List->new();
        if ($other->is_subtype_of($list)) {
            return $list;
        }

        # Otherwise return Any
        return Chalk::Grammar::Chalk::Type::Any->new();
    }
}

1;
