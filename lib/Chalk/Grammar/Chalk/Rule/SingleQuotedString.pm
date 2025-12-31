# ABOUTME: Semantic action for SingleQuotedString - builds Constant IR node with escape handling
# ABOUTME: Processes \\ and \' escape sequences, returns Constant node with Str type

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Str;

class Chalk::Grammar::Chalk::Rule::SingleQuotedString :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # SingleQuotedString -> %SINGLE_QUOTED_STRING%
        # Child [0] contains the matched string literal with quotes

        my $string_with_quotes = $context->child(0);
        die "SingleQuotedString: expected string token at child(0), got undefined - grammar bug"
            unless defined $string_with_quotes;

        # Strip surrounding single quotes
        my $value = "$string_with_quotes";
        if (length($value) >= 2 && substr($value, 0, 1) eq q{'}) {
            $value = substr($value, 1, length($value) - 2);
        }

        # Process escape sequences for single-quoted strings
        # In Perl single-quoted strings, only \' and \\ are recognized
        # All other backslash sequences are literal
        $value =~ s/\\([\\'])/$1/g;

        # Create Constant node with proper Type object
        return Chalk::IR::Node::Constant->new(
            type  => Chalk::Grammar::Chalk::Type::Str->new(),
            value => $value,
        );
    }
}

1;
