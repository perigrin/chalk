# ABOUTME: Tests for polymorphic arithmetic IR node subclasses
# ABOUTME: Verifies Add, Subtract, Multiply, Divide, and Negate nodes
use lib 'lib';
use 5.42.0;
use experimental qw(class);
use lib 'lib';
use Test::More;

plan tests => 20;

# Test 1-5: Arithmetic node subclasses should be loadable
use_ok('Chalk::IR::Node::Add');
use_ok('Chalk::IR::Node::Subtract');
use_ok('Chalk::IR::Node::Multiply');
use_ok('Chalk::IR::Node::Divide');
use_ok('Chalk::IR::Node::Negate');

# Test 6: Add node should implement op() method
{
    my $add = Chalk::IR::Node::Add->new(
        id => 10,
        inputs => [1, 2],
        left_id => 1,
        right_id => 2,
    );
    is($add->op, 'Add', 'Add node returns correct op');
}

# Test 7: Add node should have left_id and right_id accessors
{
    my $add = Chalk::IR::Node::Add->new(
        id => 11,
        inputs => [5, 6],
        left_id => 5,
        right_id => 6,
    );
    is($add->left_id, 5, 'Add node has left_id accessor');
    is($add->right_id, 6, 'Add node has right_id accessor');
}

# Test 9: Subtract node should implement op() method
{
    my $sub = Chalk::IR::Node::Subtract->new(
        id => 12,
        inputs => [7, 8],
        left_id => 7,
        right_id => 8,
    );
    is($sub->op, 'Subtract', 'Subtract node returns correct op');
}

# Test 10: Multiply node should implement op() method
{
    my $mul = Chalk::IR::Node::Multiply->new(
        id => 13,
        inputs => [9, 10],
        left_id => 9,
        right_id => 10,
    );
    is($mul->op, 'Multiply', 'Multiply node returns correct op');
}

# Test 11: Divide node should implement op() method
{
    my $div = Chalk::IR::Node::Divide->new(
        id => 14,
        inputs => [11, 12],
        left_id => 11,
        right_id => 12,
    );
    is($div->op, 'Divide', 'Divide node returns correct op');
}

# Test 12: Negate node should implement op() method
{
    my $neg = Chalk::IR::Node::Negate->new(
        id => 15,
        inputs => [13],
        operand_id => 13,
    );
    is($neg->op, 'Negate', 'Negate node returns correct op');
}

# Test 13: Negate node should have operand_id accessor
{
    my $neg = Chalk::IR::Node::Negate->new(
        id => 16,
        inputs => [20],
        operand_id => 20,
    );
    is($neg->operand_id, 20, 'Negate node has operand_id accessor');
}

# Test 14: Polymorphism - calling op() on different arithmetic nodes
{
    my @nodes = (
        Chalk::IR::Node::Add->new(id => 100, inputs => [1, 2], left_id => 1, right_id => 2),
        Chalk::IR::Node::Subtract->new(id => 101, inputs => [3, 4], left_id => 3, right_id => 4),
        Chalk::IR::Node::Multiply->new(id => 102, inputs => [5, 6], left_id => 5, right_id => 6),
        Chalk::IR::Node::Divide->new(id => 103, inputs => [7, 8], left_id => 7, right_id => 8),
        Chalk::IR::Node::Negate->new(id => 104, inputs => [9], operand_id => 9),
    );

    my @ops = map { $_->op } @nodes;
    is_deeply(\@ops, ['Add', 'Subtract', 'Multiply', 'Divide', 'Negate'],
              'Polymorphic op() calls work for arithmetic nodes');
}

# Test 15: to_hash() should include attributes for Add
{
    my $add = Chalk::IR::Node::Add->new(id => 200, inputs => [10, 20], left_id => 10, right_id => 20);
    my $hash = $add->to_hash();
    is($hash->{attributes}{left_id}, 10, 'Add to_hash() includes left_id');
    is($hash->{attributes}{right_id}, 20, 'Add to_hash() includes right_id');
}

# Test 17: to_hash() should include attributes for Negate
{
    my $neg = Chalk::IR::Node::Negate->new(id => 201, inputs => [30], operand_id => 30);
    my $hash = $neg->to_hash();
    is($neg->to_hash()->{attributes}{operand_id}, 30, 'Negate to_hash() includes operand_id');
}

# Test 18: All arithmetic nodes inherit from Base
{
    my $add = Chalk::IR::Node::Add->new(id => 300, inputs => [1, 2], left_id => 1, right_id => 2);
    isa_ok($add, 'Chalk::IR::Node::Base', 'Add node');
}

# Test 19-20: Binary operations have consistent interface
{
    my $mul = Chalk::IR::Node::Multiply->new(id => 400, inputs => [50, 60], left_id => 50, right_id => 60);
    is($mul->left_id, 50, 'Multiply has left_id');
    is($mul->right_id, 60, 'Multiply has right_id');
}

done_testing();
