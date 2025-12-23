# ABOUTME: Specialized composite semiring for Chalk IR generation
# ABOUTME: Combines syntax validation (via ChalkSyntax) and semantic IR building
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::IR::Node::Scope;
use Chalk::Semiring::ChalkSyntax;
use Chalk::Semiring::Semantic;
use Chalk::Semiring::Composite;
use Chalk::Grammar::Chalk;  # Load all Chalk Rule classes for semantic actions
use Chalk::FunctionRegistry;

class Chalk::Semiring::ChalkIR :isa(Chalk::Semiring) {
    field $grammar :param :reader;
    field $scope :reader = Chalk::IR::Node::Scope->new();
    field $function_registry :reader = Chalk::FunctionRegistry->new();
    field $composite :reader;

    ADJUST {
        # Create ChalkSyntax semiring for validation
        # Includes precedence, boolean, semantic validation, and type inference
        my $chalksyntax_sr = Chalk::Semiring::ChalkSyntax->new(
            grammar => $grammar
        );

        # Create Semantic semiring with scope and function registry in environment
        my $semantic_sr = Chalk::Semiring::Semantic->new(
            grammar => $grammar,
            env => { scope => $scope, function_registry => $function_registry }
        );

        # Use Composite with ChalkSyntax and Semantic
        # ChalkSyntax validates syntax (precedence, types, semantics)
        # Semantic builds IR via Rule classes creating nodes directly
        $composite = Chalk::Semiring::Composite->new(
            semirings => [$chalksyntax_sr, $semantic_sr]
        );
    }

    # Delegate semiring methods to composite
    method mul_id() { $composite->mul_id }
    method add_id() { $composite->add_id }
    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        $composite->init_element_from_rule($rule, $start_pos, $end_pos, $matched_value)
    }
    method multiply($x, $y) { $composite->multiply($x, $y) }
    method plus($x, $y) { $composite->plus($x, $y) }
    method semirings() { $composite->semirings }

    # Delegate on_complete() to composite (which delegates to wrapped semirings)
    method on_complete($completed_item, $completed_element, $metadata_element = undef) {
        $composite->on_complete($completed_item, $completed_element, $metadata_element)
    }

    # Delegate on_scan() to composite (which delegates to wrapped semirings)
    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        $composite->on_scan($item, $element, $pos, $matched_value, $pattern_name)
    }
}

1;
