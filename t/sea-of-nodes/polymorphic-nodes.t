# ABOUTME: Tests for polymorphic IR node class hierarchy
# ABOUTME: Verifies that node subclasses properly implement the polymorphic interface
use lib 'lib';
use 5.42.0;
use experimental qw(class);
use lib 'lib';
use Test::More;

# Test plan: We'll test the polymorphic node hierarchy incrementally
# Starting with basic nodes: Constant, Start, Return

plan tests => 15;

# Test 1: Base class should be loadable
use_ok('Chalk::IR::Node::Base') or BAIL_OUT("Cannot load Base class");

# Test 2-4: Basic node subclasses should be loadable
use_ok('Chalk::IR::Node::Constant');
use_ok('Chalk::IR::Node::Start');
use_ok('Chalk::IR::Node::Return');

# Test 5: Constant node should implement op() method
{
    my $const = Chalk::IR::Node::Constant->new(
        id => 1,
        inputs => [],
        value => 42,
        type => 'Int',
    );
    is($const->op, 'Constant', 'Constant node returns correct op');
}

# Test 6: Constant node should have value accessor
{
    my $const = Chalk::IR::Node::Constant->new(
        id => 2,
        inputs => [],
        value => 99,
        type => 'Int',
    );
    is($const->value, 99, 'Constant node has value accessor');
}

# Test 7: Start node should implement op() method
{
    my $start = Chalk::IR::Node::Start->new(
        id => 3,
        inputs => [],
        function_name => 'main',
        params => undef,
    );
    is($start->op, 'Start', 'Start node returns correct op');
}

# Test 8: Start node should have function_name accessor
{
    my $start = Chalk::IR::Node::Start->new(
        id => 4,
        inputs => [],
        function_name => 'test_fn',
        params => undef,
    );
    is($start->function_name, 'test_fn', 'Start node has function_name accessor');
}

# Test 9: Return node should implement op() method
{
    my $return = Chalk::IR::Node::Return->new(
        id => 5,
        inputs => [1, 2],  # value_id, control_id
        value_id => 1,
        control_id => 2,
    );
    is($return->op, 'Return', 'Return node returns correct op');
}

# Test 10: Return node should have value_id accessor
{
    my $return = Chalk::IR::Node::Return->new(
        id => 6,
        inputs => [10, 20],
        value_id => 10,
        control_id => 20,
    );
    is($return->value_id, 10, 'Return node has value_id accessor');
}

# Test 11: Polymorphism - calling op() on different node types
{
    my @nodes = (
        Chalk::IR::Node::Constant->new(id => 7, inputs => [], value => 1, type => 'Int'),
        Chalk::IR::Node::Start->new(id => 8, inputs => [], function_name => 'main', params => undef),
        Chalk::IR::Node::Return->new(id => 9, inputs => [7, 8], value_id => 7, control_id => 8),
    );

    my @ops = map { $_->op } @nodes;
    is_deeply(\@ops, ['Constant', 'Start', 'Return'], 'Polymorphic op() calls work correctly');
}

# Test 12: All nodes should have id accessor
{
    my $const = Chalk::IR::Node::Constant->new(id => 100, inputs => [], value => 5, type => 'Int');
    is($const->id, 100, 'Node has id accessor');
}

# Test 13: All nodes should have inputs accessor
{
    my $return = Chalk::IR::Node::Return->new(id => 101, inputs => [50, 60], value_id => 50, control_id => 60);
    is_deeply($return->inputs, [50, 60], 'Node has inputs accessor');
}

# Test 14: to_hash() should work for all nodes
{
    my $const = Chalk::IR::Node::Constant->new(id => 102, inputs => [], value => 42, type => 'Int');
    my $hash = $const->to_hash();
    is($hash->{id}, 102, 'to_hash() includes id');
}

# Test 15: to_hash() should include op
{
    my $const = Chalk::IR::Node::Constant->new(id => 103, inputs => [], value => 42, type => 'Int');
    my $hash = $const->to_hash();
    is($hash->{op}, 'Constant', 'to_hash() includes op');
}

done_testing();
