package Chalk::Grammar::BNF::Rule::PatternDef;
# ABOUTME: Semantic action for PatternDef - builds pattern definition rule
# ABOUTME: Extracts pattern name and regex content (currently returns undef to skip)

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::PatternDef :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # PatternDef -> '%' NAME '%' WS '=' WS '/' REGEX '/' FLAGS
        # or
        # PatternDef -> '%' NAME '%' WS '=' WS '//' REGEX '//' FLAGS
        #
        # Children structure depends on which alternative matched
        # Both have same indices: [1]=name, [7]=regex, [9]=flags

        my @children = @{$context->children};

        # Extract pattern name (child 1)
        my $name_child = $children[1];
        my $name = $name_child->focus;

        # Extract regex content (child 7)
        my $regex_child = $children[7];
        my $regex_content = $regex_child->focus;

        # Extract flags (child 9, optional - may not have a child if empty match)
        my $flags = '';
        if (defined $children[9]) {
            $flags = $children[9]->focus // '';
        }

        # Compile the regex with flags
        my $compiled_regex;
        if ($flags ne '') {
            $compiled_regex = qr/(?$flags:$regex_content)/;
        } else {
            $compiled_regex = qr/$regex_content/;
        }

        # Store in pattern table (env->{patterns})
        my $env = $context->env;
        $env->{patterns}->{$name} = $compiled_regex;

        # Return undef to signal this should be filtered from grammar rules
        # (pattern definitions are metadata, not grammar productions)
        return undef;
    }
}

1;
