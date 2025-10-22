# ABOUTME: Semantic action for Line rules - extracts grammar rules and ignores comments
# ABOUTME: Returns the rule content or undef for comments/blank lines
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::Line :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        my $children = $context->children();
        my @children = map { $_->extract() } $children->@*;

        # Line -> GrammarRule '\n'
        # Line -> PatternDef '\n'
        # Return the first child (the actual content, not the newline)
        if (@children >= 1) {
            return $children[0];
        }

        # Line -> BlankLine or Line -> Comment '\n'
        # Return undef to signal this should be filtered out
        return;
    }
}

