# ABOUTME: Semantic action for Word rule in Chalk grammar
# ABOUTME: Passes through Identifier or ':' Identifier for qw() word lists
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Word :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Word -> Identifier (pass through)
        # Word -> ':' Identifier (pass through colon-prefixed identifier)
        return $context->child(0);
    }
}

1;
