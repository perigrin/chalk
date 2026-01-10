# ABOUTME: Specialized composite semiring for Chalk IR generation
# ABOUTME: Uses ChalkSyntax for validation then builds IR with Semantic
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
        # Use ChalkSyntax for validation (Boolean → Precedence → TypeInference → SemanticValidation)
        my $chalksyntax = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);

        # Create Semantic semiring for IR building
        my $semantic_sr = Chalk::Semiring::Semantic->new(
            grammar => $grammar,
            env => { scope => $scope, function_registry => $function_registry }
        );

        # Composite: ChalkSyntax (validation) → Semantic (IR building)
        # This ensures only valid parses reach IR construction
        $composite = Chalk::Semiring::Composite->new(
            semirings => [$chalksyntax->composite, $semantic_sr]
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
