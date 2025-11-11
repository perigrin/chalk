# ABOUTME: Semantic action for RegexContent - pass-through to parent regex rule
# ABOUTME: Returns terminal token value for regex pattern rules to process

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::RegexContent :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # RegexContent -> %REGEX_CONTENT%
        # Pass through the terminal token to parent rule
        return $context->child(0);
    }
}

1;
