# ABOUTME: Semantic action for Comment - returns undef to filter out comments
# ABOUTME: Comments are ignored during grammar construction

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::Comment :isa(Chalk::GrammarRule) {

    method evaluate($context) {

        # Comments are ignored in grammar construction
        return;
    }
}

