#!/usr/bin/env perl
# ABOUTME: Debug script to verify Store node implementation
# ABOUTME: Tests that my $x = 42; creates proper Store and Return nodes
use 5.42.0;
use lib 'lib';
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Parser;
use Chalk::Semiring::ChalkSyntax;
use Chalk::Semiring::Semantic;
use Chalk::Semiring::Composite;
use Chalk::IR::Builder;
use Chalk::IR::Node::Scope;
use Data::Dumper;

open my $fh, '<:utf8', 'grammar/chalk.bnf' or die $!;
my $bnf = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf, 'Program', 'Chalk');

my $builder = Chalk::IR::Builder->new();
my $graph = $builder->graph;
my $scope = Chalk::IR::Node::Scope->new();

# ChalkSyntax for validation, Semantic for IR building
my $chalksyntax = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);
my $semantic = Chalk::Semiring::Semantic->new(
    grammar => $grammar,
    env     => { ir_builder => $builder, scope => $scope }
);
my $composite = Chalk::Semiring::Composite->new(
    semirings => [$chalksyntax, $semantic]
);

my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $composite);

$ENV{DEBUG_IR} = 1;
say "=== Parsing 'my \$x = 42;' ===";
my $result = $parser->parse_string('my $x = 42;');

say "\n=== Nodes in graph ===";
my $nodes = $graph->nodes;
for my $id (sort keys %$nodes) {
    my $node = $nodes->{$id};
    my $op = $node->op;
    my $inputs = join(", ", $node->inputs->@*);
    say "  $id: $op [inputs: $inputs]";
    if ($op eq 'Store') {
        say "    -> var_name: " . $node->var_name;
        say "    -> value_id: " . $node->value_id;
        say "    -> control_id: " . ($node->control_id // 'undef');
    }
    if ($op eq 'Return') {
        say "    -> value_id: " . $node->value_id;
        say "    -> control_id: " . ($node->control_id // 'undef');
    }
}
