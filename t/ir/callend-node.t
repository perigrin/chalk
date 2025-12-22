# ABOUTME: Tests for CallEnd IR node
# ABOUTME: Verifies CallEnd node for call completion projections (Chapter 18)

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::CallEnd;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::Type::Int;
use Scalar::Util 'blessed', 'refaddr';

# Create a fresh graph for tests
my $graph = Chalk::IR::Graph->new();

# Helper to create a Call node
sub make_call {
    my $callee = Chalk::IR::Node::Constant->new(
        value => 'test_func',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    return Chalk::IR::Node::Call->new(
        callee => $callee,
        args => [],
    );
}

subtest 'CallEnd node basic structure' => sub {
    my $call = make_call();
    my $call_end = Chalk::IR::Node::CallEnd->new(
        call => $call,
    );

    ok(defined($call_end), 'CallEnd node is defined');
    ok(blessed($call_end), 'CallEnd node is blessed');
    ok($call_end->isa('Chalk::IR::Node::CallEnd'), 'CallEnd node has correct type');
};

subtest 'CallEnd node op method' => sub {
    my $call = make_call();
    my $call_end = Chalk::IR::Node::CallEnd->new(
        call => $call,
    );

    is($call_end->op, 'CallEnd', 'op() returns CallEnd');
};

subtest 'CallEnd node accessors' => sub {
    my $call = make_call();
    my $call_end = Chalk::IR::Node::CallEnd->new(
        call => $call,
    );

    is($call_end->call, $call, 'call accessor works');
};

subtest 'CallEnd node to_hash' => sub {
    my $call = make_call();
    my $call_end = Chalk::IR::Node::CallEnd->new(
        call => $call,
    );

    my $hash = $call_end->to_hash;
    is($hash->{op}, 'CallEnd', 'to_hash op is CallEnd');
    is($hash->{id}, $call_end->id, 'to_hash id matches');
    ok(exists $hash->{attributes}, 'to_hash has attributes');
    is($hash->{attributes}{call_id}, $call->id, 'attributes has call_id');
};

subtest 'CallEnd node inputs include call' => sub {
    my $call = make_call();
    my $call_end = Chalk::IR::Node::CallEnd->new(
        call => $call,
    );

    my $inputs = $call_end->inputs;
    is(ref($inputs), 'ARRAY', 'inputs returns arrayref');
    ok(scalar(@$inputs) >= 1, 'inputs has at least 1 element');
    is($inputs->[0], $call->id, 'First input is call id');
};

# ===== Projection tests (#397) =====

subtest 'CallEnd ctrl_proj returns Proj node' => sub {
    my $call = make_call();
    my $call_end = Chalk::IR::Node::CallEnd->new(
        call => $call,
    );

    my $ctrl = $call_end->ctrl_proj;
    ok(defined($ctrl), 'ctrl_proj returns defined value');
    ok(blessed($ctrl), 'ctrl_proj returns blessed object');
    is($ctrl->op, 'Proj', 'ctrl_proj returns Proj node');
    is($ctrl->label, 'ctrl', 'ctrl_proj has correct label');
    is($ctrl->index, 0, 'ctrl_proj has index 0');
    is($ctrl->source, $call_end, 'ctrl_proj source is CallEnd');
};

subtest 'CallEnd mem_proj returns Proj node' => sub {
    my $call = make_call();
    my $call_end = Chalk::IR::Node::CallEnd->new(
        call => $call,
    );

    my $mem = $call_end->mem_proj;
    ok(defined($mem), 'mem_proj returns defined value');
    ok(blessed($mem), 'mem_proj returns blessed object');
    is($mem->op, 'Proj', 'mem_proj returns Proj node');
    is($mem->label, 'mem', 'mem_proj has correct label');
    is($mem->index, 1, 'mem_proj has index 1');
    is($mem->source, $call_end, 'mem_proj source is CallEnd');
};

subtest 'CallEnd ret_proj returns Proj node' => sub {
    my $call = make_call();
    my $call_end = Chalk::IR::Node::CallEnd->new(
        call => $call,
    );

    my $ret = $call_end->ret_proj;
    ok(defined($ret), 'ret_proj returns defined value');
    ok(blessed($ret), 'ret_proj returns blessed object');
    is($ret->op, 'Proj', 'ret_proj returns Proj node');
    is($ret->label, 'ret', 'ret_proj has correct label');
    is($ret->index, 2, 'ret_proj has index 2');
    is($ret->source, $call_end, 'ret_proj source is CallEnd');
};

subtest 'CallEnd projections are cached' => sub {
    my $call = make_call();
    my $call_end = Chalk::IR::Node::CallEnd->new(
        call => $call,
    );

    # Call each projection twice
    my $ctrl1 = $call_end->ctrl_proj;
    my $ctrl2 = $call_end->ctrl_proj;
    is(refaddr($ctrl1), refaddr($ctrl2), 'ctrl_proj returns same object on repeated calls');

    my $mem1 = $call_end->mem_proj;
    my $mem2 = $call_end->mem_proj;
    is(refaddr($mem1), refaddr($mem2), 'mem_proj returns same object on repeated calls');

    my $ret1 = $call_end->ret_proj;
    my $ret2 = $call_end->ret_proj;
    is(refaddr($ret1), refaddr($ret2), 'ret_proj returns same object on repeated calls');
};

done_testing();
