# ABOUTME: Tropical semiring for type inference using type lattice operations
# ABOUTME: Implements ⊕=join, ⊗=meet, 𝟘=bottom, 𝟙=top for lattice-based type checking during parsing
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::Grammar::Chalk::TypeLattice;

class Chalk::Semiring::TypeInferenceElement :isa(Chalk::Element) {
    field $type_obj :param :reader;  # Type object from Chalk::Grammar::Chalk::Type::*

    # Tropical semiring addition: join (∨) - "could be either type"
    method add( $other, $swap = undef ) {
        my $other_type = $other->type_obj;
        my $joined = $type_obj->join($other_type);
        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $joined
        );
    }

    # Tropical semiring multiplication: meet (∧) - "must satisfy all constraints"
    method multiply( $other, $swap = undef ) {
        my $other_type = $other->type_obj;
        my $meet = $type_obj->meet($other_type);
        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $meet
        );
    }

    method equals( $other, $swap = undef ) {
        return 0 unless ref($other) eq ref($self);
        # Two type elements are equal if their types have the same name
        return $type_obj->name() eq $other->type_obj->name();
    }

    method score() {
        # Score could be based on type specificity
        # More specific types (lower in lattice) score higher
        # For now, use a simple scheme: bottom=0, everything else=1
        return $type_obj->is_bottom() ? 0 : 1;
    }

    method to_string(@args) {
        return $type_obj->name();
    }

    # For backward compatibility with SemanticValidation tests
    method valid() {
        # A type is "valid" if it's not bottom (not a type contradiction)
        return !$type_obj->is_bottom();
    }
}

class Chalk::Semiring::TypeInference :isa(Chalk::Semiring) {
    field $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    # Identity elements for tropical semiring
    # 𝟘 = ⊥ (bottom) - identity for join (addition)
    # 𝟙 = ⊤ (top/Any) - identity for meet (multiplication)
    field $add_id :reader = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->bottom_type()
    );
    field $mul_id :reader = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->top_type()
    );

    # Shared context for SPPF integration (optional)
    field $shared_context :param = undef;

    # Semiring methods
    method zero() {
        return $add_id;  # Bottom type (⊥)
    }

    method one() {
        return $mul_id;  # Top type (⊤ / Any)
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        # Start with top type (no constraints yet)
        # Type constraints will be refined through meet operations
        return $mul_id;
    }

    method from_symbol($symbol, $start_pos, $end_pos, $sppf_node = undef) {
        # Infer type from IR operation if available
        # For now, return top type (Any) - constraints added via multiply
        return $mul_id;
    }

    method from_terminal($symbol, $start_pos, $end_pos) {
        # Terminals don't directly carry type information
        # Return top type - actual type inferred from context
        return $mul_id;
    }

    method multiply($x, $y) {
        # For backward compatibility if called directly
        return $x->multiply($y);
    }

    method plus($x, $y) {
        # For backward compatibility if called directly
        return $x->add($y);
    }

    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        # Hook for scanner - currently no type-based filtering
        # Could be extended to reject type mismatches during scanning
        return $element;
    }
}

1;
