package Chalk::Grammar::BNF::Rule::PatternRef;
# ABOUTME: Semantic action for PatternRef - extracts pattern reference name
# ABOUTME: Returns the pattern name without % delimiters (currently returns undef)

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::PatternRef :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # PatternRef -> '%' NAME '%'
        # Children: [0]='%', [1]=NAME, [2]='%'

        my @children = @{$context->children};

        # Extract pattern name (child 1)
        my $name_child = $children[1];
        my $name = $name_child->focus;

        # Look up pattern in env->{patterns}
        my $env = $context->env;
        my $pattern_table = $env->{patterns};

        if (exists $pattern_table->{$name}) {
            # Return the compiled regex
            return $pattern_table->{$name};
        } else {
            # Pattern not defined - this is an error
            die "Undefined pattern reference: %${name}%\n";
        }
    }
}

1;
