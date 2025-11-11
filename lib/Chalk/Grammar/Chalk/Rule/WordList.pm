# ABOUTME: Semantic action for WordList rule in Chalk grammar
# ABOUTME: Passes through Word or recursive Word WS_OPT WordList for qw() word lists
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::WordList :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # WordList -> Word (pass through)
        # WordList -> Word WS_OPT WordList (pass through first Word)
        return $context->child(0);
    }
}

1;
