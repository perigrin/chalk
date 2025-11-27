# ABOUTME: Semantic action for Statement - passes through to child statement types
# ABOUTME: Postfix conditionals are handled by PostfixConditionalStatement rule

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Statement :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Statement passes through to its single child
        # PostfixConditionalStatement handles postfix if/unless
        return $context->child(0);
    }
}

1;
