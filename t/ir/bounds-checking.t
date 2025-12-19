#!/usr/bin/env perl
# ABOUTME: Tests for array bounds checking
# ABOUTME: Verifies ArrayLoad/ArrayStore detect out-of-bounds access
use 5.42.0;
use Test2::V0;
use FindBin;
use lib "$FindBin::Bin/../../lib";

use Chalk::IR::Node::ArrayLoad;
use Chalk::IR::Node::NewArray;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Panic;
use Chalk::IR::Type::Integer;

subtest 'ArrayLoad with bounds_check flag' => sub {
    my $len = Chalk::IR::Node::Constant->new(value => 10, type => Chalk::IR::Type::Integer->TOP());
    my $arr = Chalk::IR::Node::NewArray->new(inputs => [$len->id], length => $len);
    my $idx = Chalk::IR::Node::Constant->new(value => 5, type => Chalk::IR::Type::Integer->TOP());

    my $load = Chalk::IR::Node::ArrayLoad->new(
        inputs => [$arr->id, $idx->id],
        array_id => $arr->id,
        index_id => $idx->id,
        array => $arr,
        index => $idx,
        bounds_check => 1,
    );

    ok($load->can('bounds_check'), 'ArrayLoad has bounds_check accessor');
    is($load->bounds_check, 1, 'bounds_check is enabled');
};

subtest 'ArrayLoad bounds check elimination (safe)' => sub {
    my $len = Chalk::IR::Node::Constant->new(value => 10, type => Chalk::IR::Type::Integer->TOP());
    my $arr = Chalk::IR::Node::NewArray->new(inputs => [$len->id], length => $len);
    my $idx = Chalk::IR::Node::Constant->new(value => 5, type => Chalk::IR::Type::Integer->TOP());

    my $load = Chalk::IR::Node::ArrayLoad->new(
        inputs => [$arr->id, $idx->id],
        array_id => $arr->id,
        index_id => $idx->id,
        array => $arr,
        index => $idx,
        bounds_check => 1,
    );

    my $result = $load->peephole();
    # Should still be ArrayLoad but with bounds_check potentially removed
    ok($result->isa('Chalk::IR::Node::ArrayLoad'), 'Result is ArrayLoad');
};

subtest 'ArrayLoad bounds check to Panic (always fails)' => sub {
    my $len = Chalk::IR::Node::Constant->new(value => 10, type => Chalk::IR::Type::Integer->TOP());
    my $arr = Chalk::IR::Node::NewArray->new(inputs => [$len->id], length => $len);
    my $idx = Chalk::IR::Node::Constant->new(value => 15, type => Chalk::IR::Type::Integer->TOP());

    my $load = Chalk::IR::Node::ArrayLoad->new(
        inputs => [$arr->id, $idx->id],
        array_id => $arr->id,
        index_id => $idx->id,
        array => $arr,
        index => $idx,
        bounds_check => 1,
    );

    my $result = $load->peephole();
    ok($result->isa('Chalk::IR::Node::Panic'), 'Out-of-bounds access becomes Panic');
};

done_testing();
