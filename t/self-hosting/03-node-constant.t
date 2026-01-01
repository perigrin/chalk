#!/usr/bin/env perl
# ABOUTME: Self-hosting test - compile Node::Constant to XS
# ABOUTME: Tier 2: core IR node modules (depend on Tier 1 types)

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

# Test Node::Constant compilation
subtest 'Compile Chalk::IR::Node::Constant to XS' => sub {
    my $result = compile_module(
        'lib/Chalk/IR/Node/Constant.pm',
        'Chalk::IR::Node::Constant'
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

            my $loaded = eval { require Chalk::IR::Node::Constant; 1 };
            ok($loaded, 'Node::Constant module loaded from XS');

            # Test basic functionality
            if ($loaded) {
                my $node = eval {
                    Chalk::IR::Node::Constant->new(
                        value => 42,
                        type => Chalk::IR::Type::Integer->new()
                    );
                };
                ok(defined $node, 'Node::Constant object created');
                is($node->value, 42, 'Constant value accessor works') if defined $node;
            }
        }
    }
};

done_testing();
