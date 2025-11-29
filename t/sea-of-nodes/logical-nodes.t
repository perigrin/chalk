# ABOUTME: Tests for polymorphic logical IR node subclasses
# ABOUTME: Verifies And, Or, Not, and DefinedOr nodes using v2 API
use lib 'lib';
use 5.42.0;
use experimental qw(class);
use lib 'lib';
use Test::More;

plan tests => 20;

# Test 1-4: Logical node subclasses should be loadable
use_ok('Chalk::IR::Node::And');
use_ok('Chalk::IR::Node::Or');
use_ok('Chalk::IR::Node::Not');
use_ok('Chalk::IR::Node::DefinedOr');
use_ok('Chalk::IR::Node::Constant');

# Helper to create constant nodes for testing
sub make_const {
    my ($val) = @_;
    return Chalk::IR::Node::Constant->new(value => $val, type => 'Int');
}

# Test 6: And node should implement op() method
{
    my $left = make_const(1);
    my $right = make_const(2);
    my $and = Chalk::IR::Node::And->new(left => $left, right => $right);
    is($and->op, 'And', 'And node returns correct op');
}

# Test 7-8: And node should have left and right accessors
{
    my $left = make_const(5);
    my $right = make_const(6);
    my $and = Chalk::IR::Node::And->new(left => $left, right => $right);
    is($and->left->id, $left->id, 'And node has left accessor');
    is($and->right->id, $right->id, 'And node has right accessor');
}

# Test 9: Or node should implement op() method
{
    my $left = make_const(7);
    my $right = make_const(8);
    my $or = Chalk::IR::Node::Or->new(left => $left, right => $right);
    is($or->op, 'Or', 'Or node returns correct op');
}

# Test 10-11: Or node should have left and right accessors
{
    my $left = make_const(9);
    my $right = make_const(10);
    my $or = Chalk::IR::Node::Or->new(left => $left, right => $right);
    is($or->left->id, $left->id, 'Or node has left accessor');
    is($or->right->id, $right->id, 'Or node has right accessor');
}

# Test 12: Not node should implement op() method
{
    my $operand = make_const(1);
    my $not = Chalk::IR::Node::Not->new(operand => $operand);
    is($not->op, 'Not', 'Not node returns correct op');
}

# Test 13: Not node should have operand accessor
{
    my $operand = make_const(42);
    my $not = Chalk::IR::Node::Not->new(operand => $operand);
    is($not->operand->id, $operand->id, 'Not node has operand accessor');
}

# Test 14: DefinedOr node should implement op() method
{
    my $left = make_const(11);
    my $right = make_const(12);
    my $dor = Chalk::IR::Node::DefinedOr->new(left => $left, right => $right);
    is($dor->op, 'DefinedOr', 'DefinedOr node returns correct op');
}

# Test 15-16: DefinedOr node should have left and right accessors
{
    my $left = make_const(13);
    my $right = make_const(14);
    my $dor = Chalk::IR::Node::DefinedOr->new(left => $left, right => $right);
    is($dor->left->id, $left->id, 'DefinedOr node has left accessor');
    is($dor->right->id, $right->id, 'DefinedOr node has right accessor');
}

# Test 17: Polymorphism - calling op() on different logical nodes
{
    my $c1 = make_const(1);
    my $c2 = make_const(2);
    my $c3 = make_const(3);
    my $c4 = make_const(4);
    my $c5 = make_const(5);
    my $c6 = make_const(6);
    my @nodes = (
        Chalk::IR::Node::And->new(left => $c1, right => $c2),
        Chalk::IR::Node::Or->new(left => $c3, right => $c4),
        Chalk::IR::Node::DefinedOr->new(left => $c5, right => $c6),
    );

    my @ops = map { $_->op } @nodes;
    is_deeply(\@ops, ['And', 'Or', 'DefinedOr'],
              'Polymorphic op() calls work for logical nodes');
}

# Test 18-19: to_hash() should include attributes for And
{
    my $left = make_const(10);
    my $right = make_const(20);
    my $and = Chalk::IR::Node::And->new(left => $left, right => $right);
    my $hash = $and->to_hash();
    is($hash->{attributes}{left_id}, $left->id, 'And to_hash() includes left_id');
    is($hash->{attributes}{right_id}, $right->id, 'And to_hash() includes right_id');
}

# Test 20: Content-addressable IDs work correctly
{
    my $left = make_const(50);
    my $right = make_const(60);
    my $or = Chalk::IR::Node::Or->new(left => $left, right => $right);
    like($or->id, qr/^or_const_Int_50_const_Int_60$/, 'Or has content-addressable id');
}

done_testing();
