# ABOUTME: Semantic action for String - builds Constant IR node for string literals
# ABOUTME: Converts string literals to Constant nodes with type 'String'

use 5.42.0;
use experimental 'class';
use Chalk::Grammar::Chalk::Type::Str;

class Chalk::Grammar::Chalk::Rule::String :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        # String -> %STRING%  (double-quoted string literal)
        # String -> %SQSTRING%  (single-quoted string literal)
        # String -> %VERSION% (version number like 5.42.0)
        # Child [0] contains the matched string literal with quotes

        my $string_with_quotes = $context->child(0);
        die "String: expected string token at child(0), got undefined - grammar bug" unless defined $string_with_quotes;

        # Strip surrounding quotes - see issue #201 for proper interpolation handling
        my $value = "$string_with_quotes";
        if (length($value) >= 2 && $value =~ /^['"]/) {
            $value = substr($value, 1, length($value) - 2);
        }

        # Create Constant node with proper Type object
        return Chalk::IR::Node::Constant->new(
            type  => Chalk::Grammar::Chalk::Type::Str->new(),
            value => $value,
        );
    }
}

1;
