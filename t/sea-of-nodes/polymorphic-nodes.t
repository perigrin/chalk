# ABOUTME: Tests for polymorphic IR node class hierarchy
# ABOUTME: Verifies that node subclasses properly implement the polymorphic interface
use lib 'lib';
use 5.42.0;
use experimental qw(class);
use lib 'lib';
use Test::More;

# Test plan: We'll test the polymorphic node hierarchy incrementally
# Starting with basic nodes: Constant, Start, Return

plan tests => 16;

# Test 1: Base class should be loadable
use_ok('Chalk::IR::Node::Base') or BAIL_OUT("Cannot load Base class");

# Test 2-4: Basic node subclasses should be loadable
use_ok('Chalk::IR::Node::Constant');
use_ok('Chalk::IR::Node::Start');
use_ok('Chalk::IR::Node::Return');
use_ok('Chalk::IR::Type::Integer');

# Test 5: Constant node should implement op() method
{
    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42),
    );
    is($const->op, 'Constant', 'Constant node returns correct op');
}

# Test 6: Constant node should have value accessor
{
    my $const = Chalk::IR::Node::Constant->new(
        value => 99,
        type => Chalk::IR::Type::Integer->constant(99),
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
    my $value = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::IR::Type::Integer->constant(1)
    );
    my $return = Chalk::IR::Node::Return->new(
        value => $value,
        control => $start,
    );
    is($return->op, 'Return', 'Return node returns correct op');
}

# Test 10: Return node should have value accessor
{
    my $start = Chalk::IR::Node::Start->new(function_name => 'main');
    my $value = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->constant(10)
    );
    my $return = Chalk::IR::Node::Return->new(
        value => $value,
        control => $start,
    );
    is($return->value->id, $value->id, 'Return node has value accessor');
}

# Test 11: Polymorphism - calling op() on different node types
{
    my $const = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::IR::Type::Integer->constant(1)
    );
    my $start = Chalk::IR::Node::Start->new(function_name => 'main', params => undef);
    my $return = Chalk::IR::Node::Return->new(value => $const, control => $start);
    my @nodes = ($const, $start, $return);

    my @ops = map { $_->op } @nodes;
    is_deeply(\@ops, ['Constant', 'Start', 'Return'], 'Polymorphic op() calls work correctly');
}

# Test 12: All nodes should have id accessor (numeric refaddr)
{
    my $const = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5)
    );
    like($const->id, qr/^\d+$/, 'Constant node has numeric id (refaddr)');
}

# Test 13: All nodes should have inputs accessor (computed from control and value)
{
    my $start = Chalk::IR::Node::Start->new(function_name => 'main');
    my $value = Chalk::IR::Node::Constant->new(
        value => 50,
        type => Chalk::IR::Type::Integer->constant(50)
    );
    my $return = Chalk::IR::Node::Return->new(value => $value, control => $start);
    # Return node computes inputs from control and value: [control.id, value.id]
    is_deeply($return->inputs, [$start->id, $value->id], 'Return node has computed inputs [control, value]');
}

# Test 15: to_hash() should work for all nodes (numeric refaddr id)
{
    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42)
    );
    my $hash = $const->to_hash();
    like($hash->{id}, qr/^\d+$/, 'to_hash() includes numeric id (refaddr)');
}

# Test 16: to_hash() should include op
{
    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42)
    );
    my $hash = $const->to_hash();
    is($hash->{op}, 'Constant', 'to_hash() includes op');
}

done_testing();
