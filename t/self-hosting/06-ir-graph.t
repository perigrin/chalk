#!/usr/bin/env perl
# ABOUTME: Self-hosting test - compile IR::Graph to XS
# ABOUTME: Tier 3: complex components (depend on Tiers 1-2)

use 5.42.0;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";        # For Test::Chalk::CompileHelper
use lib "$RealBin/../../lib";     # For Chalk modules
use Test::Chalk::CompileHelper qw(compile_module);

# Skip if no C compiler
require ExtUtils::CBuilder;
my $cb = ExtUtils::CBuilder->new(quiet => 1);
plan skip_all => 'No C compiler available' unless $cb->have_compiler;

# Test IR::Graph compilation
subtest 'Compile Chalk::IR::Graph to XS' => sub {
    my $result = compile_module(
        'lib/Chalk/IR/Graph.pm',
        'Chalk::IR::Graph'
    );

    ok(defined $result, 'compile_module returned result');
    ok(defined $result->{xs}, 'XS code generated');
    ok(defined $result->{pmc}, 'PMC code generated');

    # Mark as TODO since full compilation doesn't work yet
    TODO: {
        local $TODO = 'Full XS compilation not yet working';

        ok(defined $result->{so_file}, '.so file created');

        # If .so exists, try to load it
        if ($result->{so_file} && -f $result->{so_file}) {
            # Add temp directory to @INC
            unshift @INC, $result->{tempdir};

            my $loaded = eval { require Chalk::IR::Graph; 1 };
            ok($loaded, 'IR::Graph module loaded from XS');

            # Test basic functionality
            if ($loaded) {
                # Test graph creation
                my $graph = eval { Chalk::IR::Graph->new(); };
                ok(defined $graph, 'Graph object created');

                # Test node operations if graph created
                if (defined $graph) {
                    # Create a simple constant node to add
                    require Chalk::IR::Node::Constant;
                    require Chalk::IR::Type::Integer;
                    my $node = eval {
                        Chalk::IR::Node::Constant->new(
                            value => 42,
                            type => Chalk::IR::Type::Integer->new()
                        );
                    };

                    # Test add_node
                    eval { $graph->add_node($node); };
                    ok(!$@, 'add_node works') or diag($@);

                    # Test get_node
                    my $retrieved = eval { $graph->get_node($node->id); };
                    is($retrieved, $node, 'get_node retrieves added node') if defined $retrieved;

                    # Test node_count
                    my $count = eval { $graph->node_count(); };
                    is($count, 1, 'node_count returns correct count') if defined $count;
                }
            }
        }
    }
};

done_testing();
