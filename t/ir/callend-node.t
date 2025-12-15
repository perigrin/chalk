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

done_testing();
