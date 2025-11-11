# ABOUTME: Semantic action for RegexPattern - builds Constant IR node for qr// regex patterns
# ABOUTME: Converts qr// regex patterns to Constant nodes with type 'Regex'

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::RegexPattern :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # RegexPattern -> 'qr' '/' RegexContent '/' RegexFlags
        # Children: [0]='qr', [1]='/', [2]=RegexContent, [3]='/', [4]=RegexFlags

        my $builder = $context->env->{ir_builder};
        return undef unless $builder;

        # Get regex content (child 2) and flags (child 4)
        my $content = $context->child(2) // '';
        my $flags = $context->child(4) // '';

        # Build pattern string (for now, just concatenate)
        # Full regex engine implementation is tracked in issue #157
        my $pattern = "qr/$content/$flags";

        # Build and return Constant IR node with type 'Regex'
        return $builder->build_constant_node($pattern, 'Regex');
    }
}

1;
