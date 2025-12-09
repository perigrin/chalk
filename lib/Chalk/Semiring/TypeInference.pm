# ABOUTME: Tropical semiring for type inference using type lattice operations
# ABOUTME: Implements ⊕=join, ⊗=meet, 𝟘=bottom, 𝟙=top for lattice-based type checking during parsing
# See docs/type-system.md for complete type hierarchy (Int <: Num <: Str) and semantics
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::Grammar::Chalk::TypeLattice;

class Chalk::Semiring::TypeInferenceElement :isa(Chalk::Element) {
    field $type_obj :param :reader;       # Type object from Chalk::Grammar::Chalk::Type::*
    field $type_env :param :reader = {};  # Variable → Type bindings (hashref)
    field $children :param :reader = [];  # Child elements (parse tree) (arrayref)
    field $token :param :reader = undef;  # Token for terminals

    # Tropical semiring addition: join (∨) - "could be either type"
    method add( $other, $swap = undef ) {
        my $other_type = $other->type_obj;
        my $joined = $type_obj->join($other_type);
        # Note: type_env is not merged in add (alternative branches)
        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $joined,
            type_env => $type_env,
            children => $children,
            token => $token
        );
    }

    # Structural multiplication - builds parse tree without type inference
    # Type inference happens in on_complete() where we have grammar rule context
    method multiply( $other, $swap = undef ) {
        # Merge type environments (right side wins on conflicts)
        my $combined_env = { %$type_env, %{$other->type_env} };

        # Append completed element as child to build parse tree
        my @new_children = (@$children, $other);

        # Use top type (Any) - actual type determined by on_complete()
        # This allows grammar-specific operators like Array_Hash_map(Array, Hash)
        # to work correctly without being prematurely rejected by meet()
        my $top_type = Chalk::Grammar::Chalk::Type::Any->new();

        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $top_type,
            type_env => $combined_env,
            children => \@new_children,
            token => $token  # Preserve token from left element
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
        type_obj => $lattice->bottom_type(),
        type_env => {},
        children => [],
        token => undef
    );
    field $mul_id :reader = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->top_type(),
        type_env => {},
        children => [],
        token => undef
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
        # Extract type information from scanned Token objects
        # and combine with existing type constraints via meet (∧)
        # Also store the token for later extraction of variable names

        # Check if matched_value is a Token with type information
        if (defined $matched_value && ref($matched_value)) {
            my $type_obj;

            # Token::Int → Int type
            if ($matched_value->isa('Chalk::Grammar::Token::Int')) {
                $type_obj = $lattice->type_from_name('Int');
            }
            # Token::Float → Num type
            elsif ($matched_value->isa('Chalk::Grammar::Token::Float')) {
                $type_obj = $lattice->type_from_name('Num');
            }

            # If we extracted a type, combine it with existing element via meet
            # and store the token for later use in on_complete
            if (defined $type_obj) {
                my $type_element = Chalk::Semiring::TypeInferenceElement->new(
                    type_obj => $type_obj,
                    type_env => {},
                    children => [],
                    token => $matched_value  # Store token in terminal element
                );
                return $element->multiply($type_element);
            }
        }

        # No type information extracted - return element unchanged
        return $element;
    }

    # Helper method to create type from name (for testing and convenience)
    method type_from_name($name) {
        return $lattice->type_from_name($name);
    }
}


1;
