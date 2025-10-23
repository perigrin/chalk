# ABOUTME: Semantic action for Assignment - pass through child value or build assignment operation
# ABOUTME: Assignment is a wrapper, return child when no assignment operator present

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Assignment :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Assignment -> Ternary (pass-through)
        # Assignment -> Ternary WS_OPT '=' WS_OPT Assignment (TODO: implement Store)
        # Assignment -> Ternary WS_OPT %ASSIGN_OP% WS_OPT Assignment (TODO: compound assignment)

        # For now, just pass through the Ternary child
        # TODO: Implement actual assignment when we have variables (Chapter 3)
        return $context->child(0);
    }
}

1;
