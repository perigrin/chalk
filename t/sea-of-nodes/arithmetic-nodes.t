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

# Use Constant nodes as test operands (they have id() method)
use Chalk::IR::Node::Constant;

# Helper to create mock operands
sub make_operand($val) {
    return Chalk::IR::Node::Constant->new(value => $val, type => 'int');
}

# Test 6: Add node should implement op() method
{
    my $left = make_operand(1);
    my $right = make_operand(2);
    my $add = Chalk::IR::Node::Add->new(left => $left, right => $right);
    is($add->op, 'Add', 'Add node returns correct op');
}

# Test 7: Add node should have left and right accessors
{
    my $left = make_operand(5);
    my $right = make_operand(6);
    my $add = Chalk::IR::Node::Add->new(left => $left, right => $right);
    is($add->left->id, $left->id, 'Add node has left accessor');
    is($add->right->id, $right->id, 'Add node has right accessor');
}

# Test 9: Subtract node should implement op() method
{
    my $left = make_operand(7);
    my $right = make_operand(8);
    my $sub = Chalk::IR::Node::Subtract->new(left => $left, right => $right);
    is($sub->op, 'Subtract', 'Subtract node returns correct op');
}

# Test 10: Multiply node should implement op() method
{
    my $left = make_operand(9);
    my $right = make_operand(10);
    my $mul = Chalk::IR::Node::Multiply->new(left => $left, right => $right);
    is($mul->op, 'Multiply', 'Multiply node returns correct op');
}

# Test 11: Divide node should implement op() method
{
    my $left = make_operand(11);
    my $right = make_operand(12);
    my $div = Chalk::IR::Node::Divide->new(left => $left, right => $right);
    is($div->op, 'Divide', 'Divide node returns correct op');
}

# Test 12: Negate node should implement op() method
{
    my $operand = make_operand(13);
    my $neg = Chalk::IR::Node::Negate->new(operand => $operand);
    is($neg->op, 'Negate', 'Negate node returns correct op');
}

# Test 13: Negate node should have operand accessor
{
    my $operand = make_operand(20);
    my $neg = Chalk::IR::Node::Negate->new(operand => $operand);
    is($neg->operand->id, $operand->id, 'Negate node has operand accessor');
}

# Test 14: Polymorphism - calling op() on different arithmetic nodes
{
    my @nodes = (
        Chalk::IR::Node::Add->new(left => make_operand(1), right => make_operand(2)),
        Chalk::IR::Node::Subtract->new(left => make_operand(3), right => make_operand(4)),
        Chalk::IR::Node::Multiply->new(left => make_operand(5), right => make_operand(6)),
        Chalk::IR::Node::Divide->new(left => make_operand(7), right => make_operand(8)),
        Chalk::IR::Node::Negate->new(operand => make_operand(9)),
    );

    my @ops = map { $_->op } @nodes;
    is_deeply(\@ops, ['Add', 'Subtract', 'Multiply', 'Divide', 'Negate'],
              'Polymorphic op() calls work for arithmetic nodes');
}

# Test 15: to_hash() should include attributes for Add
{
    my $left = make_operand(10);
    my $right = make_operand(20);
    my $add = Chalk::IR::Node::Add->new(left => $left, right => $right);
    my $hash = $add->to_hash();
    is($hash->{attributes}{left_id}, $left->id, 'Add to_hash() includes left_id');
    is($hash->{attributes}{right_id}, $right->id, 'Add to_hash() includes right_id');
}

# Test 17: to_hash() should include attributes for Negate
{
    my $operand = make_operand(30);
    my $neg = Chalk::IR::Node::Negate->new(operand => $operand);
    my $hash = $neg->to_hash();
    is($neg->to_hash()->{attributes}{operand_id}, $operand->id, 'Negate to_hash() includes operand_id');
}

# Test 18: All arithmetic nodes inherit from Base
TODO: {
    local $TODO = 'Issue #198: IR node inheritance inconsistency';
    my $add = Chalk::IR::Node::Add->new(left => make_operand(1), right => make_operand(2));
    isa_ok($add, 'Chalk::IR::Node::Base', 'Add node');
}

# Test 19-20: Binary operations have consistent interface
{
    my $left = make_operand(50);
    my $right = make_operand(60);
    my $mul = Chalk::IR::Node::Multiply->new(left => $left, right => $right);
    is($mul->left->id, $left->id, 'Multiply has left');
    is($mul->right->id, $right->id, 'Multiply has right');
}

done_testing();
