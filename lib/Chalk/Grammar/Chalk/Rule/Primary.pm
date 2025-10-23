# ABOUTME: Semantic action for Primary - pass through child value or build primary expression
# ABOUTME: Primary handles literals, variables, function calls, and other primary expressions

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Primary :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Primary -> Literal (pass-through)
        # Primary -> Variable (TODO: implement Load node)
        # Primary -> Identifier (TODO: bareword)
        # Primary -> Identifier '(' WS_OPT ExpressionList WS_OPT ')' (TODO: function call)
        # Primary -> ... (many other alternatives)

        # For now, just pass through the first child
        # TODO: Implement different primary expression types as needed
        return $context->child(0);
    }
}

1;
