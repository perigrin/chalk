#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

my @tests = (
    'eval q{print q{ok};};',
    'eval q{print q{ok};}, print "test";',
    'eval q{print q{ok 10};

$foo = "ok 11";
print qq{$foo};}, print $@;',
);

say "Testing eval with q{} blocks:\n";
for my $i (0..$#tests) {
    my $result = $parser->parse_string($tests[$i]) ? "✓ PASS" : "✗ FAIL";
    my $display = $tests[$i];
    $display =~ s/\n/\\n/g;
    $display = substr($display, 0, 60) . "..." if length($display) > 60;
    printf "%s  Test %d: %s\n", $result, $i+1, $display;
}
