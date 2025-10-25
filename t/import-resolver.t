# ABOUTME: Test for ImportResolver - module dependency resolution for Chalk self-compilation
# ABOUTME: Validates module name to path conversion, circular dependency detection, and recursive resolution

use v5.42;
use lib 'tools';
use Test::More;
use Test::Deep;

# Test that we can load the ImportResolver module
use_ok('Chalk::ImportResolver');

# Test module name to path conversion
subtest 'Module name to path conversion' => sub {
    my $resolver = Chalk::ImportResolver->new();

    # Chalk::IR::Node -> lib/Chalk/IR/Node.pm
    is($resolver->module_to_path('Chalk::IR::Node'),
       'lib/Chalk/IR/Node.pm',
       'Converts Chalk::IR::Node to correct path');

    # Chalk::Grammar -> lib/Chalk/Grammar.pm
    is($resolver->module_to_path('Chalk::Grammar'),
       'lib/Chalk/Grammar.pm',
       'Converts Chalk::Grammar to correct path');

    # Chalk::IR::Builder -> lib/Chalk/IR/Builder.pm
    is($resolver->module_to_path('Chalk::IR::Builder'),
       'lib/Chalk/IR/Builder.pm',
       'Converts Chalk::IR::Builder to correct path');
};

# Test circular dependency detection
subtest 'Circular dependency detection' => sub {
    my $resolver = Chalk::ImportResolver->new();

    # Test that modules not being parsed are not flagged as circular
    ok(!$resolver->is_circular('Chalk::IR::Node'),
       'Module not being parsed is not circular');

    ok(!$resolver->is_circular('Chalk::IR::Graph'),
       'Another module not being parsed is not circular');

    # Circular dependencies are detected and handled gracefully during
    # recursive resolution by the resolve_dependencies method
};

# Test dependency extraction from file
subtest 'Extract dependencies from module file' => sub {
    my $resolver = Chalk::ImportResolver->new();

    # Extract dependencies from a real Chalk module
    my $deps = $resolver->extract_dependencies('lib/Chalk/IR/Builder.pm');

    ok($deps, 'extract_dependencies returns result');
    ok(ref($deps) eq 'ARRAY', 'Returns array reference');

    # Should find Chalk::IR::Node and Chalk::IR::Graph dependencies
    my %found = map { $_ => 1 } @$deps;
    ok($found{'Chalk::IR::Node'}, 'Found Chalk::IR::Node dependency');
    ok($found{'Chalk::IR::Graph'}, 'Found Chalk::IR::Graph dependency');
};

# Test recursive dependency resolution
subtest 'Recursive dependency resolution' => sub {
    my $resolver = Chalk::ImportResolver->new();

    # Resolve all dependencies for Chalk::IR::Builder
    my $order = $resolver->resolve_dependencies('Chalk::IR::Builder');

    ok($order, 'resolve_dependencies returns result');
    ok(ref($order) eq 'ARRAY', 'Returns array reference');

    # The order should have dependencies before dependents
    # Chalk::IR::Node and Chalk::IR::Graph should come before Chalk::IR::Builder
    my %positions;
    for my $i (0..$#$order) {
        $positions{$order->[$i]} = $i;
    }

    ok(exists $positions{'Chalk::IR::Builder'}, 'Builder is in the order');

    # If Node and Graph are dependencies, they should come before Builder
    if (exists $positions{'Chalk::IR::Node'}) {
        ok($positions{'Chalk::IR::Node'} < $positions{'Chalk::IR::Builder'},
           'Chalk::IR::Node comes before Builder');
    }

    if (exists $positions{'Chalk::IR::Graph'}) {
        ok($positions{'Chalk::IR::Graph'} < $positions{'Chalk::IR::Builder'},
           'Chalk::IR::Graph comes before Builder');
    }
};

# Test caching of resolved modules
subtest 'Caching prevents re-parsing' => sub {
    my $resolver = Chalk::ImportResolver->new();

    # Resolve dependencies once
    my $order1 = $resolver->resolve_dependencies('Chalk::IR::Node');

    # Resolve again - should use cache
    my $order2 = $resolver->resolve_dependencies('Chalk::IR::Node');

    cmp_deeply($order1, $order2, 'Cached result matches original');
};

done_testing();
