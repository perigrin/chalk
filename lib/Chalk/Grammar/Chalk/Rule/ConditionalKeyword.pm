# ABOUTME: Semantic action for ConditionalKeyword - returns the conditional keyword
# ABOUTME: ConditionalKeyword handles 'if' and 'unless' keywords and passes through value

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ConditionalKeyword :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # ConditionalKeyword -> 'if' | 'unless'
        # Just pass through the keyword string
        return $context->child(0);
    }
}

1;
