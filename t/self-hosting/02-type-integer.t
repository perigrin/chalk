#!/usr/bin/env perl
# ABOUTME: Self-hosting test - compile Type::Integer to XS
# ABOUTME: Tier 1: foundational type modules (no dependencies)

use 5.42.0;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test::Chalk::CompileHelper qw(compile_module);

# Skip if no C compiler
require ExtUtils::CBuilder;
my $cb = ExtUtils::CBuilder->new(quiet => 1);
plan skip_all => 'No C compiler available' unless $cb->have_compiler;

# Test Type::Integer compilation
subtest 'Compile Chalk::IR::Type::Integer to XS' => sub {
    my $result = compile_module(
        'lib/Chalk/IR/Type/Integer.pm',
        'Chalk::IR::Type::Integer'
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

            my $loaded = eval { require Chalk::IR::Type::Integer; 1 };
            ok($loaded, 'Type::Integer module loaded from XS');

            # Test basic functionality
            if ($loaded) {
                my $type = eval { Chalk::IR::Type::Integer->new(); };
                ok(defined $type, 'Type::Integer object created');
                ok($type->is_top, 'Default Type::Integer is TOP') if defined $type;
            }
        }
    }
};

done_testing();
