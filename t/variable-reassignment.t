# ABOUTME: Test variable reassignment in the interpreter
# ABOUTME: Verifies that reassigned variables reflect new values

use v5.42;
use Test::More;
use lib 'lib';

# Load required modules
use_ok('Chalk::Parser');
use_ok('Chalk::Grammar');
use_ok('Chalk::Semiring::Semantic');
use_ok('Chalk::IR::Builder');
use_ok('Chalk::IR::Interpreter');
use_ok('Chalk::IR::Optimizer::GVN');

# Load Chalk grammar from BNF file
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Helper function to execute Chalk code via interpreter
sub execute_chalk {
    my ($code) = @_;

    # Create Builder
    my $builder = Chalk::IR::Builder->new();

    # Create Parser with semantic actions
    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => $grammar,
        env => { ir_builder => $builder }
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Parse the program
    my $parse_result = $parser->parse_string($code);
    return undef unless $parse_result;

    # Get the IR graph
    my $graph = $builder->graph;

    # Prune graph to only include nodes from the winning parse
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

    # Execute via interpreter
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    return $interpreter->execute();
}

# Test 1: Simple reassignment
{
    my $result = execute_chalk('my $x = 5; $x = 10; return $x;');
    is($result, 10, 'Simple reassignment: $x = 5 then $x = 10 should return 10');
}

# Test 2: Reassignment with arithmetic
{
    my $result = execute_chalk('my $x = 5; $x = $x + 5; return $x;');
    is($result, 10, 'Reassignment with arithmetic: $x = 5 then $x = $x + 5 should return 10');
}

# Test 3: Reassignment from another variable
{
    my $result = execute_chalk('my $x = 5; my $y = 10; $x = $y; return $x;');
    is($result, 10, 'Reassignment from another variable: $x = $y should return 10');
}

# Test 4: Multiple reassignments
{
    my $result = execute_chalk('my $x = 5; $x = 10; $x = 15; return $x;');
    is($result, 15, 'Multiple reassignments: should return 15');
}

done_testing();
