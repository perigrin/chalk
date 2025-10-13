#!/usr/bin/env perl
# ABOUTME: Test C-style for loop parsing
# ABOUTME: Verify support for for (init; condition; increment) syntax
use 5.42.0;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

my @tests = (
    # C-style for loops
    ['for (my $i = 0; $i < 10; $i++) {}',     'C-style for with my'],
    ['for ($i = 0; $i < 10; $i++) {}',        'C-style for without my'],
    ['for (my $i = 0; $i < @lines; $i++) {}', 'C-style for with array length (Heredoc.pm)'],

    # Foreach style (should already work)
    ['for my $i (0..9) {}',                   'Foreach style'],
    ['foreach my $line (@lines) {}',          'Foreach with array'],
);

foreach my $test (@tests) {
    my ($code, $desc) = @$test;
    my $result = $parser->parse_string($code);
    printf "%-45s %-50s %s\n", $code, $desc, $result ? 'PASS' : 'FAIL';
}
