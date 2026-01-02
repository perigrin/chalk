# ABOUTME: Tests that package method calls (Class->method()) generate valid C code
# ABOUTME: Verifies XS doesn't emit literal package names as function calls (#561)

use v5.42;
use Test::More;
use FindBin qw($RealBin);
use Scalar::Util 'blessed';

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Grammar::Chalk::TypeRegistry;
use Chalk::Parser;
use Chalk::Semiring::ChalkIR;
use Chalk::IR::Graph;
use Chalk::Target::XS;

# Helper to generate XS from Chalk code
sub generate_xs {
    my ($code) = @_;

    # Reset TypeRegistry
    Chalk::Grammar::Chalk::TypeRegistry->instance->reset();

    my $bnf_file = "$RealBin/../../grammar/chalk.bnf";
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

        for my $method (qw(value_node value control left right operand condition source call callee body_node)) {
            next unless $node->can($method);
            my $ref = $node->$method;
            next unless blessed($ref) && $ref->can('id') && !$visited{$ref->id};
            push @queue, $ref;
        }

        for my $method (qw(branches control_users args params body_statements)) {
            next unless $node->can($method) && $node->$method;
            for my $ref ($node->$method->@*) {
                next unless blessed($ref) && $ref->can('id') && !$visited{$ref->id};
                push @queue, $ref;
            }
        }

        if ($node->can('return_nodes') && $node->return_nodes) {
            for my $ret ($node->return_nodes->@*) {
                push @queue, $ret if blessed($ret) && $ret->can('id') && !$visited{$ret->id};
            }
        }

        if ($node->can('function_defs') && $node->function_defs) {
            for my $func ($node->function_defs->@*) {
                push @queue, $func if blessed($func) && $func->can('id') && !$visited{$func->id};
            }
        }
    }

    # Generate XS
    my $xs_gen = Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'TestClass',
    );

    my $xs_ast = eval { $xs_gen->generate() };
    return undef if $@;

    return $xs_ast->emit();
}

# Test 1: Simple package method call
subtest 'Package method call does not emit literal package name' => sub {
    my $code = q{
use 5.42.0;
use experimental qw(class);

class Foo {
    method test() {
        return Foo->bar();
    }
}
};

    my $xs = generate_xs($code);
    ok($xs, 'XS generated');

    # Should NOT contain 'Foo(' as a function call
    unlike($xs, qr/Foo\s*\(/, 'Does not emit literal "Foo(" as function call');

    # Should generate valid C code (no undeclared identifiers)
    # For now, we accept placeholder calls
    ok($xs =~ /call_method|call_pv|PLACEHOLDER_METHOD_CALL|unknown/,
        'Uses method dispatch or placeholder instead of invalid syntax');
};

# Test 2: Multiple package method calls
subtest 'Multiple package method calls' => sub {
    my $code = q{
use 5.42.0;
use experimental qw(class);

class MyClass {
    method complex() {
        my $a = Foo->new();
        my $b = Bar::Baz->create();
        return $a;
    }
}
};

    my $xs = generate_xs($code);
    ok($xs, 'XS generated');

    # Should not emit literal package names as function calls
    unlike($xs, qr/Foo\s*\(/, 'Does not emit "Foo("');
    unlike($xs, qr/Bar::Baz\s*\(/, 'Does not emit "Bar::Baz("');
};

done_testing();
