# ABOUTME: Semantic action for SingleQuotedString - pass-through to String parent rule
# ABOUTME: Returns terminal token value for String rule to process

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::SingleQuotedString :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # SingleQuotedString -> %SINGLE_QUOTED_STRING%
        # Pass through the terminal token to parent String rule
        return $context->child(0);
    }
}

1;
