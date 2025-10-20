package Chalk::Grammar::BNF::Rule::LineList;
# ABOUTME: Semantic action for LineList rules - collects lines into array
# ABOUTME: Handles empty, single line, and multiple lines recursively

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::LineList :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        my @children = map { $_->extract } $context->children->@*;

        # LineList -> []  (empty)
        if (@children == 0) {
            return [];
        }

        # LineList -> Line  (single line)
        if (@children == 1) {
            my $line = $children[0];
            return defined($line) ? [$line] : [];
        }

        # LineList -> Line LineList  (multiple lines)
        if (@children == 2) {
            my ($line, $rest) = @children;
            my @result = ();
            push @result, $line if defined($line);

            if (ref($rest) eq 'ARRAY') {
                push @result, @$rest;
            }

            return \@result;
        }

        return [];
    }
}

1;
