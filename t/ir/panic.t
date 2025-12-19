#!/usr/bin/env perl
# ABOUTME: Tests for Panic IR node
# ABOUTME: Verifies runtime error termination for bounds violations
use 5.42.0;
use Test2::V0;
use FindBin;
use lib "$FindBin::Bin/../../lib";

use Chalk::IR::Node::Panic;

subtest 'Panic node creation' => sub {
    my $panic = Chalk::IR::Node::Panic->new(
        inputs => [],
        message => 'Array index out of bounds'
    );

    is($panic->op, 'Panic', 'Panic op is correct');
    is($panic->message, 'Array index out of bounds', 'message accessor works');
};

subtest 'Panic to_hash' => sub {
    my $panic = Chalk::IR::Node::Panic->new(
        inputs => [],
        message => 'Test error',
        source_info => { line => 42 }
    );

    my $hash = $panic->to_hash();
    is($hash->{op}, 'Panic', 'to_hash op is Panic');
    is($hash->{attributes}{message}, 'Test error', 'to_hash has message');
};

done_testing();
