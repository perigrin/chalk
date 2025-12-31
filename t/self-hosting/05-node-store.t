#!/usr/bin/env perl
# ABOUTME: Self-hosting test - compile Node::Store to XS
# ABOUTME: Tier 2: core IR node modules (depend on Tier 1 types)

use 5.42.0;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test::Chalk::CompileHelper qw(compile_module);

# Skip if no C compiler
require ExtUtils::CBuilder;
my $cb = ExtUtils::CBuilder->new(quiet => 1);
plan skip_all => 'No C compiler available' unless $cb->have_compiler;

# Test Node::Store compilation
subtest 'Compile Chalk::IR::Node::Store to XS' => sub {
    my $result = compile_module(
        'lib/Chalk/IR/Node/Store.pm',
        'Chalk::IR::Node::Store'
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

            my $loaded = eval { require Chalk::IR::Node::Store; 1 };
            ok($loaded, 'Node::Store module loaded from XS');

            # Test basic functionality
            if ($loaded) {
                my $node = eval {
                    Chalk::IR::Node::Store->new(
                        var => '$x',
                        value => Chalk::IR::Node::Constant->new(
                            value => 42,
                            type => Chalk::IR::Type::Integer->new()
                        ),
                        control => Chalk::IR::Node::Start->new()
                    );
                };
                ok(defined $node, 'Node::Store object created');
                is($node->var, '$x', 'Store var accessor works') if defined $node;
            }
        }
    }
};

done_testing();
