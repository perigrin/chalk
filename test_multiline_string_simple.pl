#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

my @tests = (
    q{my $x = 'simple';},
    q{my $x = 'line1
line2';},
    q{eval 'print "test"';},
    q{eval 'while (0) {
    print "test";
}';},
);

say "Testing multi-line strings:\n";
for my $test (@tests) {
    my $result = $parser->parse_string($test) ? "✓" : "✗";
    my $display = $test;
    $display =~ s/\n/\\n/g;
    $display = substr($display, 0, 50) . "..." if length($display) > 50;
    printf "%s  %s\n", $result, $display;
}
