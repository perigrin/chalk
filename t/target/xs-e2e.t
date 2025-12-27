# ABOUTME: End-to-end tests for XS code generation from Chalk source
# ABOUTME: Tests full pipeline: source → parse → IR → XS output

use 5.42.0;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;

# Set lib path at compile time using abs_path on $0 for worktree compatibility
BEGIN {
    use Cwd qw(abs_path);
    use File::Spec;
    my $test_file = abs_path($0);
    my ($vol, $dir, $file) = File::Spec->splitpath($test_file);
    my $lib_dir = abs_path(File::Spec->catdir($vol, $dir, '..', '..', 'lib'));
    unshift @INC, $lib_dir;
}

use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Parser;
use Chalk::Semiring::ChalkIR;
use Chalk::IR::Graph;
use Chalk::Target::XS;

# Helper to generate XS from Chalk source code
sub generate_xs {
    my ($code, $module_name) = @_;
    $module_name //= 'TestModule';

    my $bnf_file = "grammar/chalk.bnf";
    open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');
    my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
    );

    my $result = $parser->parse_string($code);
    return undef unless $result;

    # Get winning node
    my $winning_node;
    if ($result->can('context')) {
        my $ctx = $result->context;
        if ($ctx->can('focus')) {
            $winning_node = $ctx->focus;
        }
    }
    return undef unless $winning_node && blessed($winning_node) && $winning_node->can('id');

    # Build graph
    my $graph = Chalk::IR::Graph->new();
    my %visited;
    my @queue = ($winning_node);

    while (@queue) {
        my $node = shift @queue;
        next unless blessed($node) && $node->can('id');
        my $node_id = $node->id;
        next if $visited{$node_id}++;

        $graph->add_node($node);

        # Traverse node references
        for my $method (qw(value_node value control left right operand condition source call callee)) {
            next unless $node->can($method);
            my $ref = $node->$method;
            next unless blessed($ref) && $ref->can('id') && !$visited{$ref->id};
            push @queue, $ref;
        }

        # Handle arrays
        for my $method (qw(branches control_users args)) {
            next unless $node->can($method) && $node->$method;
            for my $ref ($node->$method->@*) {
                next unless blessed($ref) && $ref->can('id') && !$visited{$ref->id};
                push @queue, $ref;
            }
        }

        # Traverse return_nodes for Stop
        if ($node->can('return_nodes') && $node->return_nodes) {
            for my $ret ($node->return_nodes->@*) {
                push @queue, $ret if blessed($ret) && $ret->can('id') && !$visited{$ret->id};
            }
        }

        # Traverse function_defs for Stop
        if ($node->can('function_defs') && $node->function_defs) {
            for my $func ($node->function_defs->@*) {
                push @queue, $func if blessed($func) && $func->can('id') && !$visited{$func->id};
            }
        }
    }

    # Generate XS
    my $xs_target = Chalk::Target::XS->new(
        graph => $graph,
        module_name => $module_name,
    );

    my $xs_ast = $xs_target->generate();
    return $xs_ast->emit();
}

# ===== Test 1: Simple function with explicit return =====
subtest 'Function with explicit return constant' => sub {
    my $code = 'sub answer { return 42; }';
    my $xs = generate_xs($code, 'TestMod');

    ok(defined $xs, 'XS generated');
    diag "Generated XS:\n$xs" if $ENV{TEST_VERBOSE};

    like($xs, qr/MODULE = TestMod/, 'Has MODULE line');
    like($xs, qr/IV answer\(\)/, 'Function signature with correct name and return type');
    like($xs, qr/IV tmp_\d+ = 42/, 'Has constant 42');
    like($xs, qr/RETVAL = tmp_\d+/, 'Has RETVAL assignment');
};

# ===== Test 2: Simple arithmetic =====
subtest 'Function with arithmetic expression' => sub {
    my $code = 'sub add { return 1 + 2; }';
    my $xs = generate_xs($code, 'TestMod');

    ok(defined $xs, 'XS generated');
    diag "Generated XS:\n$xs" if $ENV{TEST_VERBOSE};

    like($xs, qr/add\(\)/, 'Function named correctly');
    # Should have constant-folded result or arithmetic
    like($xs, qr/(?:IV tmp_\d+ = 3|tmp_\d+ \+ tmp_\d+)/, 'Has folded constant or arithmetic');
    like($xs, qr/RETVAL = tmp_\d+/, 'Has RETVAL assignment');
};

# ===== Test 3: Function with parameters =====
subtest 'Function with parameters' => sub {
    my $code = 'sub add($x, $y) { return $x + $y; }';
    my $xs = generate_xs($code, 'TestMod');

    ok(defined $xs, 'XS generated');
    diag "Generated XS:\n$xs" if $ENV{TEST_VERBOSE};

    # Parameters should appear in signature
    like($xs, qr/add\s*\([^)]*x[^)]*y[^)]*\)/, 'Parameters in signature');

    # Should have addition operation
    like($xs, qr/\+/, 'Has addition operator');
    like($xs, qr/RETVAL/, 'Has RETVAL');
};

# ===== Test 4: Multiple functions =====
subtest 'Multiple function definitions' => sub {
    my $code = 'sub foo { return 1; } sub bar { return 2; }';
    my $xs = generate_xs($code, 'TestMod');

    ok(defined $xs, 'XS generated');
    diag "Generated XS:\n$xs" if $ENV{TEST_VERBOSE};

    like($xs, qr/foo\(\)/, 'Has foo function');
    like($xs, qr/bar\(\)/, 'Has bar function');
};

# ===== Test 5: Comparison operation =====
subtest 'Function with comparison' => sub {
    my $code = 'sub is_positive($n) { return $n > 0; }';
    my $xs = generate_xs($code, 'TestMod');

    ok(defined $xs, 'XS generated');
    diag "Generated XS:\n$xs" if $ENV{TEST_VERBOSE};

    like($xs, qr/is_positive/, 'Function named correctly');
    # Should have comparison operator
    like($xs, qr/>/, 'Has greater-than operator');
};

# ===== Test 6: Function call =====
subtest 'Function with function call' => sub {
    my $code = 'sub double($x) { return $x + $x; } sub quad($x) { return double(double($x)); }';
    my $xs = generate_xs($code, 'TestMod');

    ok(defined $xs, 'XS generated');
    diag "Generated XS:\n$xs" if $ENV{TEST_VERBOSE};

    like($xs, qr/double/, 'Has double function');
    like($xs, qr/quad/, 'Has quad function');

    # Should have function call
    like($xs, qr/double\([^)]+\)/, 'Has function call to double');
};

# ===== Test 7: Implicit return (last expression) =====
subtest 'Function with implicit return' => sub {
    my $code = 'sub compute { 1 + 2 }';
    my $xs = generate_xs($code, 'TestMod');

    ok(defined $xs, 'XS generated');
    diag "Generated XS:\n$xs" if $ENV{TEST_VERBOSE};

    like($xs, qr/compute/, 'Function named correctly');

    # Implicit return should still set RETVAL
    like($xs, qr/RETVAL\s*=/, 'Has RETVAL assignment for implicit return');
};

done_testing();
