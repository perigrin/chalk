#!/usr/bin/env perl
use 5.038;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

my @tests = (
    'my $x = q{test};',
    'my $x = q{test}; my $y = q{test2};',
    'eval q{print "test";};',
    'eval q{my $x = "test";};',
    'my $x = q{q{test}};',  # nested q{} in q{}
    'eval q{my $x = q{test};};',  # q{} inside eval q{}
);

say "Testing nested q{} blocks:\n";
for my $i (0..$#tests) {
    my $result = $parser->parse_string($tests[$i]) ? "✓ PASS" : "✗ FAIL";
    printf "%s  Test %d: %s\n", $result, $i+1, $tests[$i];
}
