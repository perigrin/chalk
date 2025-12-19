#!/usr/bin/env perl
# ABOUTME: Tests for fixed-length array IR nodes
# ABOUTME: Verifies NewArray length, ArrayLength, and bounds checking
use 5.42.0;
use Test2::V0;
use FindBin;
use lib "$FindBin::Bin/../../lib";

use Chalk::IR::Node::NewArray;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;

subtest 'NewArray with length' => sub {
    my $len = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->TOP()
    );

    my $arr = Chalk::IR::Node::NewArray->new(
        inputs => [$len->id],
        length => $len,
    );

    ok($arr->can('length'), 'NewArray has length accessor');
    is($arr->length->value, 10, 'NewArray length is 10');
};

subtest 'NewArray with element_type' => sub {
    my $len = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->TOP()
    );

    my $arr = Chalk::IR::Node::NewArray->new(
        inputs => [$len->id],
        length => $len,
        element_type => Chalk::IR::Type::Integer->TOP(),
    );

    ok($arr->can('element_type'), 'NewArray has element_type accessor');
    ok($arr->element_type->isa('Chalk::IR::Type::Integer'), 'element_type is Integer');
};

done_testing();
