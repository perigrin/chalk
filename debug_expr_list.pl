#!/usr/bin/env perl
use v5.42;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Parser;
use Chalk::Semiring::ChalkIR;
use Data::Dumper;

# Load grammar
my $bnf_file = "$RealBin/grammar/chalk.bnf";
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'UseStatement', 'Chalk');

my $code = q{use overload
    '""'  => 'value',
    'eq'  => '_string_eq',
    'cmp' => '_string_cmp'};

my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
my $parser = Chalk::Parser->new(
    grammar => $grammar,
    semiring => $semiring,
);

my $result = $parser->parse_string($code);

if ($result && $result->can('context')) {
    my $ctx = $result->context;
    if ($ctx && $ctx->can('focus')) {
        my $node = $ctx->focus;
        say "Node op: " . ($node->op // 'undef');
        say "Node attributes: " . Dumper($node->attributes);
    }
}
