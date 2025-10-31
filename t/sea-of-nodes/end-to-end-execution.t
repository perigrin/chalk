# ABOUTME: End-to-end integration test for Parser → Builder → Interpreter pipeline
# ABOUTME: Verifies Chalk can parse, build IR, and execute simple programs

use v5.42;
use Test::More;

# Load all required modules
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

# Test 1: Simple arithmetic with variable
subtest 'Execute: my $x = 3 + 5; return $x * 2;' => sub {
    # Step 1: Create Builder
    my $builder = Chalk::IR::Builder->new();

    # Step 2: Create Parser with semantic actions that build IR
    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => $grammar,
        env => { ir_builder => $builder }
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Step 3: Parse the program
    my $code = 'my $x = 3 + 5; return $x * 2;';
    my $parse_result = $parser->parse_string($code);
    ok($parse_result, 'Program parses successfully');

    # Step 4: Get the IR graph
    my $graph = $builder->graph;
    ok($graph, 'Builder has IR graph');

    my $nodes_before = scalar(keys %{$graph->nodes});
    ok($nodes_before > 0, "Graph has nodes before GVN (got $nodes_before)");

    # Run GVN optimizer to deduplicate nodes (now preserves polymorphic types!)
    my $gvn_result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    $graph = $gvn_result->{graph};

    my $nodes_after = scalar(keys %{$graph->nodes});
    ok($nodes_after > 0, "Graph has nodes after GVN (got $nodes_after)");
    diag("GVN: $nodes_before nodes -> $nodes_after nodes");

    # Step 6: Create interpreter
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    ok($interpreter, 'Interpreter created');

    # Step 7: Execute the program
    my $result = $interpreter->execute();

    # Step 8: Verify result
    is($result, 16, 'Execution result: (3 + 5) * 2 = 16');
};

# Test 2: Just return a constant
subtest 'Execute: return 42;' => sub {
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

    my $code = 'return 42;';
    my $parse_result = $parser->parse_string($code);
    ok($parse_result, 'Program parses successfully');

    my $graph = $builder->graph;
    my $gvn_result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    $graph = $gvn_result->{graph};

    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 42, 'Execution result: return 42');
};

# Test 3: Simple arithmetic without variable
subtest 'Execute: return 3 + 5;' => sub {
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

    my $code = 'return 3 + 5;';
    my $parse_result = $parser->parse_string($code);
    ok($parse_result, 'Program parses successfully');

    my $graph = $builder->graph;
    my $gvn_result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    $graph = $gvn_result->{graph};

    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 8, 'Execution result: 3 + 5 = 8');
};

# Test 4: More complex computation with multiple variables
subtest 'Execute: Complex multi-variable computation' => sub {
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

    # Compute: (a + b) * (c - d) where a=10, b=5, c=8, d=3
    # Expected: (10 + 5) * (8 - 3) = 15 * 5 = 75
    my $code = q{
        my $a = 10;
        my $b = 5;
        my $c = 8;
        my $d = 3;
        my $sum = $a + $b;
        my $diff = $c - $d;
        my $result = $sum * $diff;
        return $result;
    };

    my $parse_result = $parser->parse_string($code);
    ok($parse_result, 'Complex program parses successfully');

    my $graph = $builder->graph;
    my $nodes_before = scalar(keys %{$graph->nodes});
    ok($nodes_before > 0, "Graph has nodes before GVN (got $nodes_before)");

    my $gvn_result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    $graph = $gvn_result->{graph};

    my $nodes_after = scalar(keys %{$graph->nodes});
    ok($nodes_after > 0, "Graph has nodes after GVN (got $nodes_after)");
    diag("GVN: $nodes_before nodes -> $nodes_after nodes");

    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 75, 'Execution result: (10+5) * (8-3) = 75');
};

# Test 5: Nested arithmetic operations
subtest 'Execute: Nested arithmetic with intermediate results' => sub {
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

    # Compute: ((x * 2) + (y * 3)) - z where x=4, y=5, z=7
    # Expected: ((4*2) + (5*3)) - 7 = (8 + 15) - 7 = 23 - 7 = 16
    my $code = q{
        my $x = 4;
        my $y = 5;
        my $z = 7;
        my $x2 = $x * 2;
        my $y3 = $y * 3;
        my $sum = $x2 + $y3;
        return $sum - $z;
    };

    my $parse_result = $parser->parse_string($code);
    ok($parse_result, 'Nested arithmetic program parses successfully');

    my $graph = $builder->graph;
    my $gvn_result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    $graph = $gvn_result->{graph};

    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 16, 'Execution result: ((4*2)+(5*3))-7 = 16');
};

done_testing();
