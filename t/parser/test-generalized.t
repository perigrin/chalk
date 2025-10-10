#!/usr/bin/env perl
# ABOUTME: Test generalized goal checking without artificial start rules
# ABOUTME: Should work with natural grammars that have multiple start symbol rules
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;

# Test without artificial start rule - E can derive multiple ways
my $grammar = Chalk::Grammar->build_grammar(
    [ 'E' => [qw(E + T)] ],   # First rule - was causing issues before
    [ 'E' => ['T'] ],         # Second rule - should also work
    [ 'T' => ['num'] ],
);

say "Start symbol: " . $grammar->start_symbol;

my $parser = Chalk::Parser->new(grammar => $grammar);

# Test simple case that uses E -> T -> num
my $result = $parser->parse_string('num');
say "num: " . (defined $result ? "SUCCESS - $result" : "FAIL");

# Test case that uses E -> E + T
$result = $parser->parse_string('num+num');
say "num + num: " . (defined $result ? "SUCCESS - $result" : "FAIL");

ok defined($parser->parse_string('num')), "Parse simple num without artificial start rule";
ok defined($parser->parse_string('num+num')), "Parse addition without artificial start rule";