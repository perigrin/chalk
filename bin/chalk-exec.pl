#!/usr/bin/env perl
# ABOUTME: Wrapper script to execute Chalk code via CEK interpreter
# ABOUTME: Takes Chalk source code as argument, compiles to IR, executes with CEK
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Parser;
use Chalk::Grammar;
use Chalk::Semiring::Semantic;
use Chalk::IR::Builder;
use Chalk::IR::Optimizer::GVN;
use Chalk::Interpreter::CEKDataflow;

my $code = $ARGV[0] or die "Usage: $0 'chalk code'\n";

# Load grammar
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Parse and compile
my $builder = Chalk::IR::Builder->new();
my $semiring = Chalk::Semiring::Semantic->new(
    grammar => $grammar,
    env => { ir_builder => $builder }
);
my $parser = Chalk::Parser->new(
    grammar => $grammar,
    semiring => $semiring,
    preprocess => ['Chalk::Preprocessor::Heredoc']
);

my $parse_result = $parser->parse_string($code) or die "Parse failed\n";
my $graph = $builder->graph;

# Prune to winning parse
if ($parse_result->can('context')) {
    my $ctx = $parse_result->context;
    if ($ctx->can('focus')) {
        my $winning_node = $ctx->focus;
        if ($winning_node && $winning_node->can('id')) {
            $graph->prune_to_reachable($winning_node->id);
        }
    }
}

# Run GVN optimizer
my $gvn_result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
$graph = $gvn_result->{graph};

# Execute with CEK
my $cek = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
my $result = $cek->execute();
print $result;
