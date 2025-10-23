# ABOUTME: Semantic action for LogicalAnd - pass through child value or build logical AND operation
# ABOUTME: LogicalAnd is a wrapper, return child when no && operator present

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::LogicalAnd :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # LogicalAnd -> Comparison (pass-through)
        # LogicalAnd -> LogicalAnd WS_OPT '&&' WS_OPT Comparison (TODO: implement)
        # LogicalAnd -> LogicalAnd WS_OPT 'and' WS_OPT Comparison (TODO: implement)

        # For now, just pass through the Comparison child
        return $context->child(0);
    }
}

1;
