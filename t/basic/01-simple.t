#!/usr/bin/env perl
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

my $grammar = Grammar->build_grammar( [ 'A' => [] ] );
ok $grammar, $grammar;

my $parser = Parser->new( grammar => $grammar );
$parser->parse_tokens('A');

