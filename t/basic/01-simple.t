#!/usr/bin/env perl
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Test::Chalk::Grammar;
use Chalk::Grammar;
use Chalk::Parser;

my $grammar = Test::Chalk::Grammar->build_grammar(
    rules => [
        [ 'A' => [] ]
    ]
);
ok $grammar, $grammar;

my $parser = Chalk::Parser->new( grammar => $grammar );
$parser->parse_string('A');

