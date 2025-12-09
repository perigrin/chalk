#!/usr/bin/env perl
# ABOUTME: Tests TypeInference and Semantic semiring integration via Composite
# ABOUTME: Verifies that Semantic's evaluate() can access TypeInference's type_env
use 5.42.0;
use Test::More;
use Scalar::Util qw(blessed);

use Chalk::Parser;
use Chalk::Grammar::Chalk;
use Chalk::Semiring::TypeInference;
use Chalk::Semiring::Semantic;
use Chalk::Semiring::Composite;

# Test 1: Basic type binding integration
# When parsing 'my $x = 0;':
# - TypeInference should establish $x : Int in its type_env
# - Semantic should be able to access that type_env via its EvalContext
subtest 'TypeInference type_env accessible to Semantic' => sub {
    my $code = q{my $x = 0;};

    # Create both semirings
    my $grammar = Chalk::Grammar::Chalk->new();
    my $type_sr = Chalk::Semiring::TypeInference->new();
    my $sem_sr = Chalk::Semiring::Semantic->new(grammar => $grammar);

    # Composite them
    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$type_sr, $sem_sr]
    );

    # Parse with composite
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );

    my $element = $parser->parse_string($code);
    ok(defined($element), 'Parsing succeeded');

    # Extract TypeInference element
    my $type_elem = $element->element_at(0);
    ok($type_elem->can('type_env'), 'TypeInference element has type_env');

    # Verify TypeInference established the binding
    my $type_env = $type_elem->type_env;
    ok(exists $type_env->{'$x'}, 'TypeInference established $x binding');
    is($type_env->{'$x'}->name, 'Int', 'TypeInference inferred Int type for $x');

    # Extract Semantic element
    my $sem_elem = $element->element_at(1);
    ok($sem_elem->can('context'), 'Semantic element has context');

    # THE KEY TEST: Verify Semantic's context received type_env
    my $ctx = $sem_elem->context;
    my $env_type_env = $ctx->env->{type_env};

    ok(defined($env_type_env), 'Semantic context env has type_env')
        or diag("This should be set by Semantic.on_complete() from CompositeElement metadata");

    if (defined($env_type_env)) {
        ok(exists $env_type_env->{'$x'}, 'Semantic can see $x type binding');
        is($env_type_env->{'$x'}->name, 'Int', 'Semantic sees correct Int type for $x');
    }
};

# Test 2: Multiple variable bindings
subtest 'Multiple variable type bindings flow to Semantic' => sub {
    my $code = q{my $x = 0; my $y = 1.5;};

    my $grammar = Chalk::Grammar::Chalk->new();
    my $type_sr = Chalk::Semiring::TypeInference->new();
    my $sem_sr = Chalk::Semiring::Semantic->new(grammar => $grammar);
    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$type_sr, $sem_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );

    my $element = $parser->parse_string($code);
    ok(defined($element), 'Parsing succeeded');

    # Check TypeInference captured both bindings
    my $type_elem = $element->element_at(0);
    my $type_env = $type_elem->type_env;

    ok(exists $type_env->{'$x'}, 'TypeInference has $x');
    ok(exists $type_env->{'$y'}, 'TypeInference has $y');
    is($type_env->{'$x'}->name, 'Int', '$x is Int');
    is($type_env->{'$y'}->name, 'Num', '$y is Num');

    # Check Semantic received those bindings
    my $sem_elem = $element->element_at(1);
    my $env_type_env = $sem_elem->context->env->{type_env};

    ok(defined($env_type_env), 'Semantic has type_env');

    if (defined($env_type_env)) {
        ok(exists $env_type_env->{'$x'}, 'Semantic sees $x');
        ok(exists $env_type_env->{'$y'}, 'Semantic sees $y');
        is($env_type_env->{'$x'}->name, 'Int', 'Semantic sees $x as Int');
        is($env_type_env->{'$y'}->name, 'Num', 'Semantic sees $y as Num');
    }
};

done_testing();
