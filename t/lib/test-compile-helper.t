# ABOUTME: Test suite for Test::Chalk::CompileHelper module
# ABOUTME: Validates Chalk to XS compilation workflow helper functions
use 5.42.0;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use Scalar::Util qw(blessed);

BEGIN {
    use_ok('Test::Chalk::CompileHelper', qw(
        compile_module
        parse_chalk_file
        build_ir_graph
        compile_xs
    ));
}

# Test 1: parse_chalk_file - Parse Chalk source to IR
subtest 'parse_chalk_file: Parse Token.pm successfully' => sub {
    my $token_file = 'lib/Chalk/Grammar/Token.pm';
    plan skip_all => "Cannot find $token_file" unless -f $token_file;

    my $ir_root = parse_chalk_file($token_file);

    ok(defined $ir_root, 'parse_chalk_file returns defined result');
    ok(blessed($ir_root) && $ir_root->can('id'), 'Returned IR node has id method');
};

# Test 2: build_ir_graph - Build graph from IR root
subtest 'build_ir_graph: Create valid graph structure' => sub {
    my $token_file = 'lib/Chalk/Grammar/Token.pm';
    plan skip_all => "Cannot find $token_file" unless -f $token_file;

    my $ir_root = parse_chalk_file($token_file);
    skip 'parse_chalk_file failed', 2 unless defined $ir_root;

    my $graph = build_ir_graph($ir_root);

    ok(defined $graph, 'build_ir_graph returns defined graph');
    ok(blessed($graph) && $graph->isa('Chalk::IR::Graph'), 'Graph is a Chalk::IR::Graph');

    # Check that graph has nodes
    my @nodes = $graph->nodes;
    ok(scalar(@nodes) > 0, 'Graph contains nodes');
};

# Test 3: compile_xs - Compile XS file to .so
subtest 'compile_xs: Compile XS to shared library' => sub {
    require ExtUtils::CBuilder;
    my $cb = ExtUtils::CBuilder->new(quiet => 1);
    plan skip_all => 'No C compiler available' unless $cb->have_compiler;

    # Create minimal test XS file
    my $tempdir = tempdir(CLEANUP => 1);
    my $xs_file = File::Spec->catfile($tempdir, 'TestModule.xs');

    open my $fh, '>', $xs_file or die "Cannot write $xs_file: $!";
    print $fh q{
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

MODULE = TestModule  PACKAGE = TestModule

int
test_function()
    CODE:
        RETVAL = 42;
    OUTPUT:
        RETVAL
};
    close $fh;

    my $so_file = compile_xs($xs_file, 'TestModule');

    ok(defined $so_file, 'compile_xs returns defined result');
    ok(-f $so_file, 'Compiled .so file exists') if defined $so_file;
};

# Test 4: compile_module - End-to-end compilation
subtest 'compile_module: Full Chalk to XS compilation workflow' => sub {
    require ExtUtils::CBuilder;
    my $cb = ExtUtils::CBuilder->new(quiet => 1);
    plan skip_all => 'No C compiler available' unless $cb->have_compiler;

    my $token_file = 'lib/Chalk/Grammar/Token.pm';
    plan skip_all => "Cannot find $token_file" unless -f $token_file;

    my $result = compile_module($token_file, 'Chalk::Grammar::Token');

    ok(defined $result, 'compile_module returns defined result');

    TODO: {
        local $TODO = 'Full compilation may not work yet';

        ok(defined $result->{xs}, 'Result contains XS code');
        ok(defined $result->{pmc}, 'Result contains PMC code');
        ok(defined $result->{so_file}, 'Result contains .so file path');
        ok(-f $result->{so_file}, 'Compiled .so file exists') if defined $result->{so_file};
    }
};

done_testing;
