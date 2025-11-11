# ABOUTME: Semantic action for QuotedWordList rule in Chalk grammar
# ABOUTME: Extracts WordList from qw(...) syntax by passing through child(2)
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::QuotedWordList :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # QuotedWordList -> 'qw' '(' WordList ')'
        # Return the WordList (child 2)
        return $context->child(2);
    }
}

1;
