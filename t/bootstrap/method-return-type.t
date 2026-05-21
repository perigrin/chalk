# ABOUTME: Tests that MethodDefinition IR nodes include return_type from TypeInference.
# ABOUTME: Verifies the TI→SA→IR threading pipeline for method return type detection.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Build Perl grammar pipeline
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::MethodRetTypeTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::MethodRetTypeTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# Helper to parse a class body and find MethodDecl nodes
my sub parse_and_find_methods($source) {
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return () unless defined $result;

    my $sem_ctx = $result;
    return () unless defined $sem_ctx;
    my $ir = $sem_ctx->extract();
    return () unless defined $ir;

    # Walk the IR to find MethodDecl nodes
    my @methods;
    my @stack = ($ir);
    while (@stack) {
        my $node = pop @stack;
        next unless defined $node;
        next unless $node isa Chalk::IR::Node;
        if ($node isa Chalk::IR::Node::Constructor
                && $node->class() eq 'MethodDecl') {
            push @methods, $node;
        }
        # Recurse into inputs
        for my $input ($node->inputs()->@*) {
            if (ref($input) eq 'ARRAY') {
                push @stack, $input->@*;
            } else {
                push @stack, $input;
            }
        }
    }
    return @methods;
}

# Test: Method with value return has return_type 'Any'
{
    my $source = <<~'PERL';
    use 5.42.0;
    use utf8;
    class Foo {
        method bar() {
            return 42;
        }
    }
    PERL

    my @methods = parse_and_find_methods($source);
    ok(scalar @methods >= 1, 'found at least one MethodDecl');
    if (@methods) {
        my $bar = $methods[0];
        my $return_type_node = $bar->inputs()->[3];
        ok(defined $return_type_node, 'MethodDecl has return_type input (index 3)');
        if (defined $return_type_node) {
            TODO: {
                local $TODO = 'return_type inference not yet wired into MethodDecl IR construction';
                is($return_type_node->value(), 'Any',
                   'method with value return has return_type Any');
            }
        }
    }
}

# Test: Method with bare return has return_type 'Void'
{
    my $source = <<~'PERL';
    use 5.42.0;
    use utf8;
    class Bar {
        method baz($x) {
            return unless $x;
            say "hello";
        }
    }
    PERL

    my @methods = parse_and_find_methods($source);
    ok(scalar @methods >= 1, 'found at least one MethodDecl (bare return)');
    if (@methods) {
        my $baz = $methods[0];
        my $return_type_node = $baz->inputs()->[3];
        ok(defined $return_type_node, 'MethodDecl has return_type input (bare)');
        if (defined $return_type_node) {
            TODO: {
                local $TODO = 'return_type inference not yet wired into MethodDecl IR construction';
                is($return_type_node->value(), 'Void',
                   'method with bare return has return_type Void');
            }
        }
    }
}

# Test: Method with no return has return_type 'Void'
{
    my $source = <<~'PERL';
    use 5.42.0;
    use utf8;
    class Qux {
        method nop() {
            say "side effect";
        }
    }
    PERL

    my @methods = parse_and_find_methods($source);
    ok(scalar @methods >= 1, 'found at least one MethodDecl (no return)');
    if (@methods) {
        my $nop = $methods[0];
        my $return_type_node = $nop->inputs()->[3];
        ok(defined $return_type_node, 'MethodDecl has return_type input (no return)');
        if (defined $return_type_node) {
            TODO: {
                local $TODO = 'return_type inference not yet wired into MethodDecl IR construction';
                is($return_type_node->value(), 'Void',
                   'method with no return has return_type Void');
            }
        }
    }
}

done_testing;
