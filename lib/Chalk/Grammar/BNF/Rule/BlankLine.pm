# ABOUTME: Semantic action for BlankLine - returns undef to filter out blank lines
# ABOUTME: Blank lines are ignored during grammar construction

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::BlankLine :isa(Chalk::GrammarRule) {

    method evaluate($context) {

        # Blank lines are ignored in grammar construction
        return;
    }
}

