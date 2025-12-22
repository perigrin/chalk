# ABOUTME: Tests for Call IR node
# ABOUTME: Verifies Call node for function/method invocation (Chapter 18)

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::Type::Int;
use Scalar::Util 'blessed', 'refaddr';

# Create a fresh graph for tests
my $graph = Chalk::IR::Graph->new();

subtest 'Call node basic structure' => sub {
    my $callee = Chalk::IR::Node::Constant->new(
        value => 'my_function',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $arg1 = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    my $call = Chalk::IR::Node::Call->new(
        callee => $callee,
        args => [$arg1],
    );

    ok(defined($call), 'Call node is defined');
    ok(blessed($call), 'Call node is blessed');
    ok($call->isa('Chalk::IR::Node::Call'), 'Call node has correct type');
};

subtest 'Call node op method' => sub {
    my $callee = Chalk::IR::Node::Constant->new(
        value => 'test',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $call = Chalk::IR::Node::Call->new(
        callee => $callee,
        args => [],
    );

    is($call->op, 'Call', 'op() returns Call');
};

subtest 'Call node accessors' => sub {
    my $callee = Chalk::IR::Node::Constant->new(
        value => 'func',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    my $arg1 = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    my $arg2 = Chalk::IR::Node::Constant->new(
        value => 2,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    my $call = Chalk::IR::Node::Call->new(
        callee => $callee,
        args => [$arg1, $arg2],
    );

    is($call->callee, $callee, 'callee accessor works');
    is(scalar(@{$call->args}), 2, 'args has correct count');
    is($call->args->[0], $arg1, 'First arg is correct');
    is($call->args->[1], $arg2, 'Second arg is correct');
};

subtest 'Call node with receiver for method calls' => sub {
    my $receiver = Chalk::IR::Node::Constant->new(
        value => 'MyClass',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    my $callee = Chalk::IR::Node::Constant->new(
        value => 'new',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $call = Chalk::IR::Node::Call->new(
        callee => $callee,
        args => [],
        receiver => $receiver,
    );

    is($call->receiver, $receiver, 'receiver accessor works');
};

subtest 'Call node to_hash' => sub {
    my $callee = Chalk::IR::Node::Constant->new(
        value => 'test',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $call = Chalk::IR::Node::Call->new(
        callee => $callee,
        args => [],
    );

    my $hash = $call->to_hash;
    is($hash->{op}, 'Call', 'to_hash op is Call');
    is($hash->{id}, $call->id, 'to_hash id matches');
    ok(exists $hash->{attributes}, 'to_hash has attributes');
    is($hash->{attributes}{callee_id}, $callee->id, 'attributes has callee_id');
};

subtest 'Call node has rpc identifier' => sub {
    my $callee = Chalk::IR::Node::Constant->new(
        value => 'test',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $call = Chalk::IR::Node::Call->new(
        callee => $callee,
        args => [],
    );

    ok(defined($call->rpc), 'rpc is defined');
    like($call->rpc, qr/^rpc_\d+$/, 'rpc has expected format');
};

# ===== Execute tests (#396) =====

subtest 'Call execute returns call descriptor' => sub {
    my $callee = Chalk::IR::Node::Constant->new(
        value => 'my_func',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    my $arg1 = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    my $arg2 = Chalk::IR::Node::Constant->new(
        value => 'hello',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $call = Chalk::IR::Node::Call->new(
        callee => $callee,
        args => [$arg1, $arg2],
    );

    # Create mock context that returns node values
    my %node_values = (
        $callee->id => 'my_func',
        $arg1->id => 42,
        $arg2->id => 'hello',
    );
    my $context = sub ($key) {
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1};
        }
        return undef;
    };

    my $result = $call->execute($context);
    ok(defined($result), 'execute returns defined value');
    is(ref($result), 'HASH', 'execute returns hashref');
    is($result->{func_name}, 'my_func', 'descriptor has func_name');
    is_deeply($result->{args}, [42, 'hello'], 'descriptor has evaluated args');
    is($result->{rpc}, $call->rpc, 'descriptor has rpc');
};

subtest 'Call execute with no arguments' => sub {
    my $callee = Chalk::IR::Node::Constant->new(
        value => 'no_args_func',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $call = Chalk::IR::Node::Call->new(
        callee => $callee,
        args => [],
    );

    my %node_values = (
        $callee->id => 'no_args_func',
    );
    my $context = sub ($key) {
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1};
        }
        return undef;
    };

    my $result = $call->execute($context);
    ok(defined($result), 'execute returns defined value');
    is($result->{func_name}, 'no_args_func', 'descriptor has func_name');
    is_deeply($result->{args}, [], 'descriptor has empty args');
};

subtest 'Call execute with receiver for method calls' => sub {
    my $receiver = Chalk::IR::Node::Constant->new(
        value => 'MyObject',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    my $callee = Chalk::IR::Node::Constant->new(
        value => 'do_something',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    my $arg = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    my $call = Chalk::IR::Node::Call->new(
        callee => $callee,
        args => [$arg],
        receiver => $receiver,
    );

    my %node_values = (
        $callee->id => 'do_something',
        $arg->id => 10,
        $receiver->id => 'MyObject',
    );
    my $context = sub ($key) {
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1};
        }
        return undef;
    };

    my $result = $call->execute($context);
    ok(defined($result), 'execute returns defined value');
    is($result->{func_name}, 'do_something', 'descriptor has method name');
    is($result->{receiver}, 'MyObject', 'descriptor has receiver');
    is_deeply($result->{args}, [10], 'descriptor has args');
};

done_testing();
