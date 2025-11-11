# ABOUTME: Semantic action for RegexFlags - pass-through to parent regex rule
# ABOUTME: Returns terminal token value for regex pattern rules to process

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::RegexFlags :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # RegexFlags -> %REGEX_FLAGS%
        # Pass through the terminal token to parent rule
        return $context->child(0);
    }
}

1;
