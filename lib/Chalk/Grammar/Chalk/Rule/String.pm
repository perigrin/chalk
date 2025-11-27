# ABOUTME: Semantic action for String - builds Constant IR node for string literals
# ABOUTME: Converts string literals to Constant nodes with type 'String'

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::String :isa(Chalk::GrammarRule) {
    use Chalk::IR::Node::Constant;

    method evaluate($context) {
        # String -> %STRING%  (double-quoted string literal)
        # String -> %SQSTRING%  (single-quoted string literal)
        # Child [0] contains the matched string literal with quotes

        my $string_with_quotes = $context->child(0);
        return undef unless defined $string_with_quotes;

        # Strip surrounding quotes (both " and ')
        my $value = "$string_with_quotes";
        if (length($value) >= 2) {
            $value = substr($value, 1, length($value) - 2);
        }

        # Create Constant node directly (content-addressable ID)
        return Chalk::IR::Node::Constant->new(
            type  => 'String',
            value => $value,
        );
    }
}

1;
