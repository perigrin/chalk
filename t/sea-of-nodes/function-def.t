#!/usr/bin/env perl
# ABOUTME: Test FunctionDef IR node for function definitions
# ABOUTME: Part of issue #133 - Function Call Support (Chapter 18)

use lib 'lib';
use 5.42.0;
use Test2::V0;
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Graph;

subtest 'FunctionDef basic structure' => sub {
    use Chalk::IR::Node::FunctionDef;

    my $func = Chalk::IR::Node::FunctionDef->new(
        name => 'add',
        parameters => ['a', 'b'],
    );

    is $func->op, 'FunctionDef', 'FunctionDef node created';
    is $func->name, 'add', 'Function has name';
    is $func->parameters, ['a', 'b'], 'Function has parameters';
    ok $func->id, 'Function has unique id';
};

subtest 'FunctionDef with body graph' => sub {
    use Chalk::IR::Node::FunctionDef;
    use Chalk::IR::Node::Constant;
    use Chalk::IR::Node::Return;
    use Chalk::IR::Node::Start;
    use Chalk::Grammar::Chalk::Type::Int;

    # Create a simple body: return 42;
    my $body_graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new();
    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::Grammar::Chalk::Type::Int->new(),
    );
    my $ret = Chalk::IR::Node::Return->new(
        value => $const,
        control => $start,
    );
    $body_graph->add_node($start);
    $body_graph->add_node($const);
    $body_graph->add_node($ret);

    my $func = Chalk::IR::Node::FunctionDef->new(
        name => 'answer',
        parameters => [],
        body_graph => $body_graph,
    );

    is $func->name, 'answer', 'Function has name';
    ok $func->body_graph, 'Function has body graph';
    isa_ok $func->body_graph, ['Chalk::IR::Graph'], 'Body is a Graph';
};

subtest 'FunctionDef to_hash serialization' => sub {
    use Chalk::IR::Node::FunctionDef;

    my $func = Chalk::IR::Node::FunctionDef->new(
        name => 'greet',
        parameters => ['name'],
    );

    my $hash = $func->to_hash;
    is $hash->{op}, 'FunctionDef', 'Serialized op is FunctionDef';
    is $hash->{attributes}{name}, 'greet', 'Serialized name';
    is $hash->{attributes}{parameters}, ['name'], 'Serialized parameters';
};

subtest 'FunctionDef inputs (no data dependencies)' => sub {
    use Chalk::IR::Node::FunctionDef;

    my $func = Chalk::IR::Node::FunctionDef->new(
        name => 'standalone',
        parameters => [],
    );

    is $func->inputs, [], 'FunctionDef has no inputs (it defines, not uses)';
};

subtest 'FunctionDef execute returns function descriptor' => sub {
    use Chalk::IR::Node::FunctionDef;
    use Chalk::IR::Graph;

    my $body_graph = Chalk::IR::Graph->new();
    my $func = Chalk::IR::Node::FunctionDef->new(
        name => 'test_func',
        parameters => ['x', 'y'],
        body_graph => $body_graph,
    );

    # execute should return descriptor that can be used for dispatch
    my $descriptor = $func->execute(sub { });

    is $descriptor->{name}, 'test_func', 'Descriptor has function name';
    is $descriptor->{parameters}, ['x', 'y'], 'Descriptor has parameters';
    ok $descriptor->{body_graph}, 'Descriptor has body graph';
};
