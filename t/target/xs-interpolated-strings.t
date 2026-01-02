# ABOUTME: End-to-end tests for interpolated string XS code generation
# ABOUTME: Tests full pipeline: source → parse → IR → XS output for string literals and interpolation

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
use Scalar::Util 'blessed';

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

        # Handle arrays including 'parts' for InterpolatedString
        for my $method (qw(branches control_users args parts)) {
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

# ===== Test 1: Double-quoted string without interpolation =====
subtest 'Double-quoted string without variables' => sub {
    my $code = q{sub msg { return "Simple message"; }};
    my $xs = generate_xs($code, 'TestMod');

    ok(defined $xs, 'XS generated');
    diag "Generated XS:\n$xs" if $ENV{TEST_VERBOSE};

    like($xs, qr/msg\(\)/, 'Function named correctly');
    # Should be treated as simple constant
    like($xs, qr/newSVpv/, 'Has newSVpv for string constant');
    like($xs, qr/Simple message/, 'String content preserved');
};

# ===== Test 2: Simple interpolation with one variable =====
subtest 'Interpolated string with single variable' => sub {
    my $code = q{sub greet($name) { return "Hello $name!"; }};
    my $xs = generate_xs($code, 'TestMod');

    ok(defined $xs, 'XS generated');
    diag "Generated XS:\n$xs" if $ENV{TEST_VERBOSE};

    like($xs, qr/greet/, 'Function named correctly');
    # Should have string concatenation - look for sv_catsv or similar
    like($xs, qr/sv_cat/, 'Has string concatenation (sv_catsv or sv_catpv)');
    # Should reference the parameter
    like($xs, qr/name/, 'References parameter name');
};

# ===== Test 3: Interpolation with multiple variables =====
subtest 'Interpolated string with multiple variables' => sub {
    my $code = q{sub full_greet($first, $last) { return "Hello $first $last!"; }};
    my $xs = generate_xs($code, 'TestMod');

    ok(defined $xs, 'XS generated');
    diag "Generated XS:\n$xs" if $ENV{TEST_VERBOSE};

    like($xs, qr/full_greet/, 'Function named correctly');
    # Should have multiple concatenations
    like($xs, qr/sv_cat/, 'Has string concatenation operations');
    # Should reference both parameters
    like($xs, qr/first/, 'References first parameter');
    like($xs, qr/last/, 'References last parameter');
};

done_testing();
