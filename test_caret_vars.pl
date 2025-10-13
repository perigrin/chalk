#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

my @tests = (
    '$^X = 1;',          # caret variable
    '${^XY} = 1;',       # caret variable in braces
    '${ ^XY } = 1;',     # caret variable in braces with space
    '$ {^XY} = 1;',      # caret variable with space before brace
    'if (${^XY} != 23) { print "test" }',
    'if ($ {^XY} != 23) { print "test" }',
);

say "Testing caret variable syntax:\n";
for my $i (0..$#tests) {
    my $result = $parser->parse_string($tests[$i]) ? "✓ PASS" : "✗ FAIL";
    printf "%s  Test %d: %s\n", $result, $i+1, $tests[$i];
}
