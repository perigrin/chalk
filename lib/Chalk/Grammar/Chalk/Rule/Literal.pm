# ABOUTME: Semantic action for Literal - pass through child value from specific literal type
# ABOUTME: Literal delegates to Number, String, etc. which build their own IR nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Literal :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Literal -> Number (Number builds Constant node)
        # Literal -> String (TODO: implement String constant)
        # Literal -> QuotedWordList (TODO: implement)
        # Literal -> RegexPattern (TODO: implement)
        # Literal -> RegexSubstitution (TODO: implement)
        # Literal -> EmptyList (TODO: implement)
        # Literal -> 'undef' (TODO: implement undef constant)

        # Just pass through - the specific literal type will build its IR node
        return $context->child(0);
    }
}

1;
