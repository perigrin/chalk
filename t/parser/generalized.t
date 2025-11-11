#!/usr/bin/env perl
# ABOUTME: Test generalized goal checking without artificial start rules
# ABOUTME: Should work with natural grammars that have multiple start symbol rules
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use lib 't/lib';
use Test::Chalk::Grammar;
use Chalk::Grammar;
use Chalk::Parser;

# Test without artificial start rule - E can derive multiple ways
my $grammar = Test::Chalk::Grammar->build_grammar(
    rules => [
        [ 'E' => [qw(E + T)] ],   # First rule - was causing issues before
        [ 'E' => ['T'] ],         # Second rule - should also work
        [ 'T' => ['num'] ],
    ]
);

my $parser = Chalk::Parser->new(grammar => $grammar);

ok defined($parser->parse_string('num')), "Parse simple num without artificial start rule";
ok defined($parser->parse_string('num+num')), "Parse addition without artificial start rule";