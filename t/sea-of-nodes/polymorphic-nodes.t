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
        value => 42,
        type => 'Int',
    );
    is($const->op, 'Constant', 'Constant node returns correct op');
}

# Test 6: Constant node should have value accessor
{
    my $const = Chalk::IR::Node::Constant->new(
        value => 99,
        type => 'Int',
    );
    is($const->value, 99, 'Constant node has value accessor');
}

# Test 7: Start node should implement op() method
{
    my $start = Chalk::IR::Node::Start->new(
        function_name => 'main',
        params => undef,
    );
    is($start->op, 'Start', 'Start node returns correct op');
}

# Test 8: Start node should have function_name accessor
{
    my $start = Chalk::IR::Node::Start->new(
        function_name => 'test_fn',
        params => undef,
    );
    is($start->function_name, 'test_fn', 'Start node has function_name accessor');
}

# Test 9: Return node should implement op() method
{
    my $start = Chalk::IR::Node::Start->new(function_name => 'main');
    my $value = Chalk::IR::Node::Constant->new(value => 1, type => 'Int');
    my $return = Chalk::IR::Node::Return->new(
        value => $value,
        control => $start,
    );
    is($return->op, 'Return', 'Return node returns correct op');
}

# Test 10: Return node should have value accessor
{
    my $start = Chalk::IR::Node::Start->new(function_name => 'main');
    my $value = Chalk::IR::Node::Constant->new(value => 10, type => 'Int');
    my $return = Chalk::IR::Node::Return->new(
        value => $value,
        control => $start,
    );
    is($return->value->id, $value->id, 'Return node has value accessor');
}

# Test 11: Polymorphism - calling op() on different node types
{
    my $const = Chalk::IR::Node::Constant->new(value => 1, type => 'Int');
    my $start = Chalk::IR::Node::Start->new(function_name => 'main', params => undef);
    my $return = Chalk::IR::Node::Return->new(value => $const, control => $start);
    my @nodes = ($const, $start, $return);

    my @ops = map { $_->op } @nodes;
    is_deeply(\@ops, ['Constant', 'Start', 'Return'], 'Polymorphic op() calls work correctly');
}

# Test 12: All nodes should have id accessor (content-addressable for Constant)
{
    my $const = Chalk::IR::Node::Constant->new(value => 5, type => 'Int');
    is($const->id, 'const_Int_5', 'Constant node has content-addressable id');
}

# Test 13: All nodes should have inputs accessor (computed from control and value)
{
    my $start = Chalk::IR::Node::Start->new(function_name => 'main');
    my $value = Chalk::IR::Node::Constant->new(value => 50, type => 'Int');
    my $return = Chalk::IR::Node::Return->new(value => $value, control => $start);
    # Return node computes inputs from control and value: [control.id, value.id]
    is_deeply($return->inputs, [$start->id, $value->id], 'Return node has computed inputs [control, value]');
}

# Test 14: to_hash() should work for all nodes (content-addressable id for Constant)
{
    my $const = Chalk::IR::Node::Constant->new(value => 42, type => 'Int');
    my $hash = $const->to_hash();
    is($hash->{id}, 'const_Int_42', 'to_hash() includes content-addressable id');
}

# Test 15: to_hash() should include op
{
    my $const = Chalk::IR::Node::Constant->new(value => 42, type => 'Int');
    my $hash = $const->to_hash();
    is($hash->{op}, 'Constant', 'to_hash() includes op');
}

done_testing();
