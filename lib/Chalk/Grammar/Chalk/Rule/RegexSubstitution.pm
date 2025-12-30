# ABOUTME: Semantic action for RegexSubstitution - builds Constant IR node for s/// patterns
# ABOUTME: Converts s/pattern/replacement/flags to Constant nodes with Regex type

use 5.42.0;
use experimental 'class';

use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Regex;

class Chalk::Grammar::Chalk::Rule::RegexSubstitution :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        # RegexSubstitution -> 's' '/' RegexContent '/' RegexContent '/' RegexFlags
        # Children: [0]='s', [1]='/', [2]=pattern, [3]='/', [4]=replacement, [5]='/', [6]=flags

        # Get pattern (child 2), replacement (child 4), and flags (child 6)
        my $pattern = $context->child(2) // '';
        my $replacement = $context->child(4) // '';
        my $flags = $context->child(6) // '';

        # Build substitution string (for now, just concatenate)
        # Full regex engine implementation is tracked in issue #157
        my $subst = "s/$pattern/$replacement/$flags";

        # Create Constant node with proper Regex type
        # Note: s/// is stored as a string for now; full regex engine will handle execution
        return Chalk::IR::Node::Constant->new(
            type  => Chalk::Grammar::Chalk::Type::Regex->new(),
            value => $subst,
        );
    }
}

1;
