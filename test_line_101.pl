#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

my @tests = (
    'my $x = "\cX";',
    '{ my $x = 1; }',
    '{ my $x = "\cX"; }',
    '$ {$x} = 1;',
    '${ $x } = 1;',
    '${x} = 1;',
);

say "Testing line 101 constructs:\n";
for my $i (0..$#tests) {
    my $result = $parser->parse_string($tests[$i]) ? "✓ PASS" : "✗ FAIL";
    printf "%s  Test %d: %s\n", $result, $i+1, $tests[$i];
}
