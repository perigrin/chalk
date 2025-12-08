# ABOUTME: DEPRECATED - Use Chalk::Semiring::SemanticValidation instead
# ABOUTME: This module exists for backwards compatibility and delegates to SemanticValidation
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::Semiring::SemanticValidation;
use Chalk::Grammar::Chalk::SemanticRules;

# DEPRECATED: TypeInferenceElement is now SemanticValidationElement
# This alias exists for backwards compatibility with existing tests
class Chalk::Semiring::TypeInferenceElement :isa(Chalk::Semiring::SemanticValidationElement) {
}

# DEPRECATED: TypeInference is now SemanticValidation
# This wrapper exists for backwards compatibility with existing tests
class Chalk::Semiring::TypeInference :isa(Chalk::Semiring) {
    field $delegate :reader;  # Delegate to SemanticValidation
    field $shared_context :param = undef;

    ADJUST {
        # Create Chalk-specific semantic rules for backwards compatibility
        my $rules = Chalk::Grammar::Chalk::SemanticRules->new();

        # Create the new SemanticValidation semiring
        $delegate = Chalk::Semiring::SemanticValidation->new(
            rules => $rules,
            shared_context => $shared_context
        );
    }

    # Delegate all semiring methods to SemanticValidation
    method zero() {
        return $delegate->zero();
    }

    method one() {
        return $delegate->one();
    }

    method from_symbol($symbol, $start_pos, $end_pos, $sppf_node = undef) {
        return $delegate->from_symbol($symbol, $start_pos, $end_pos, $sppf_node);
    }

    method from_terminal($symbol, $start_pos, $end_pos) {
        return $delegate->from_terminal($symbol, $start_pos, $end_pos);
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        return $delegate->init_element_from_rule($rule, $start_pos, $end_pos, $matched_value);
    }

    method mul_id() {
        return $delegate->mul_id();
    }

    method add_id() {
        return $delegate->add_id();
    }
}

1;
