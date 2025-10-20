package Chalk::Grammar::BNF::Rule::PatternRef;
# ABOUTME: Semantic action for PatternRef - extracts pattern reference name
# ABOUTME: Returns the pattern name without % delimiters (currently returns undef)

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::PatternRef :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # PatternRef -> '%' NAME '%'
        # For now, pattern references are not fully implemented
        # TODO: Implement pattern reference semantic actions
        return undef;
    }
}

1;
