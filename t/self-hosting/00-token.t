#!/usr/bin/env perl
# ABOUTME: Baseline self-hosting test - compile Token.pm to XS
# ABOUTME: Establishes pattern for remaining self-hosting tests

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

# Test Token.pm compilation
subtest 'Compile Chalk::Grammar::Token to XS' => sub {
    my $result = compile_module(
        'lib/Chalk/Grammar/Token.pm',
        'Chalk::Grammar::Token'
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

            my $loaded = eval { require Chalk::Grammar::Token; 1 };
            ok($loaded, 'Token module loaded from XS');

            # Test basic functionality
            if ($loaded) {
                my $token = eval { Chalk::Grammar::Token->new(value => 'test'); };
                ok(defined $token, 'Token object created');
                is($token->value, 'test', 'Token value accessor works') if defined $token;
            }
        }
    }
};

done_testing();
