# ABOUTME: Semantic action for String - builds Constant IR node for string literals
# ABOUTME: Converts string literals to Constant nodes with type 'String'

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::String :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        # String -> %STRING%  (double-quoted string literal)
        # String -> %SQSTRING%  (single-quoted string literal)
        # Child [0] contains the matched string literal with quotes

        my $string_with_quotes = $context->child(0);
        die "String: expected string token at child(0), got undefined - grammar bug" unless defined $string_with_quotes;

        # Strip surrounding quotes - see issue #201 for proper interpolation handling
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
