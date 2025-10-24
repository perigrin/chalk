# ABOUTME: Semantic action for RegexMatch - pass through child value or build regex match operation
# ABOUTME: RegexMatch is a wrapper, return child when no regex match operator present

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::RegexMatch :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # RegexMatch -> Range (pass-through)
        # RegexMatch -> RegexMatch WS_OPT %REGEX_MATCH_OP% WS_OPT Range (TODO: implement)

        # For now, just pass through the Range child
        return $context->child(0);
    }
}

1;
