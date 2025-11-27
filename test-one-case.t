#!/usr/bin/env perl
# ABOUTME: Minimal test for single issue #195 case
# ABOUTME: Tests just the failing early return case with debug output

use 5.42.0;
use experimental qw(class);
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/lib";

use Chalk::Parser;
use Chalk::Grammar;
use Chalk::Grammar::Chalk;  # Pre-loads all grammar rule classes
use Chalk::Semiring::Semantic;
use Chalk::IR::Builder;
use Chalk::IR::Node::Scope;

# Enable debug
$ENV{DEBUG_STMTLIST_DISAMBIG} = 1;

# Load grammar
open my $fh, '<:utf8', "$RealBin/grammar/chalk.bnf" or die $!;
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

sub compile_chalk {
    my ($code) = @_;

    my $builder = Chalk::IR::Builder->new();
    my $scope = Chalk::IR::Node::Scope->new();
    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => $grammar,
        env => { ir_builder => $builder, scope => $scope }
    );

    my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
    my $result = $parser->parse_string($code);

    return $result ? $builder->graph : undef;
}

# Test the failing case
my $code = 'my $x = -5; if ($x > 0) { return 42; } return -42;';
print STDERR "=== Parsing: $code ===\n";

my $graph = compile_chalk($code);
ok($graph, "Code compiled to IR");

done_testing();
