package Chalk::Grammar::BNF::Rule::Terminal;
# ABOUTME: Semantic action for Terminal - extracts string value from quoted terminal
# ABOUTME: Removes surrounding quotes and returns the terminal string

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::Terminal :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Terminal -> "'" <content> "'"
        # Children: [0] = "'" (quote)
        #           [1] = terminal content (string with possible escapes)
        #           [2] = "'" (quote)

        my @children = map { $_->extract } $context->children->@*;

        # Extract the middle element (the actual terminal value)
        if (@children >= 3) {
            my $content = $children[1];
            # Unescape backslash sequences
            # Handle standard escape sequences: \n, \t, \r, etc.
            $content =~ s/\\n/\n/g;
            $content =~ s/\\t/\t/g;
            $content =~ s/\\r/\r/g;
            $content =~ s/\\'/'/g;   # \' becomes '
            $content =~ s/\\\\/\\/g;  # \\ becomes \
            return $content;
        }

        return '';
    }
}

1;
