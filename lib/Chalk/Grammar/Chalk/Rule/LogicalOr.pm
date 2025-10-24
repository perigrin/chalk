# ABOUTME: Semantic action for LogicalOr - pass through child value or build logical OR operation
# ABOUTME: LogicalOr is a wrapper, return child when no || operator present

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::LogicalOr :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # LogicalOr -> LogicalAnd (pass-through)
        # LogicalOr -> LogicalOr WS_OPT '||' WS_OPT LogicalAnd (TODO: implement)
        # LogicalOr -> LogicalOr WS_OPT 'or' WS_OPT LogicalAnd (TODO: implement)
        # LogicalOr -> LogicalOr WS_OPT '//' WS_OPT LogicalAnd (TODO: implement)

        # For now, just pass through the LogicalAnd child
        return $context->child(0);
    }
}

1;
