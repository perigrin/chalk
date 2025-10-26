# ABOUTME: Tests for polymorphic comparison IR node subclasses
# ABOUTME: Verifies GT, LT, EQ, NE, LE, GE comparison nodes
use 5.42.0;
use experimental qw(class);
use Test::More;
use lib 'lib';

plan tests => 20;

# Test 1-6: Comparison node subclasses should be loadable
use_ok('Chalk::IR::Node::GT');
use_ok('Chalk::IR::Node::LT');
use_ok('Chalk::IR::Node::EQ');
use_ok('Chalk::IR::Node::NE');
use_ok('Chalk::IR::Node::LE');
use_ok('Chalk::IR::Node::GE');

# Test 7: GT node should implement op() method
{
    my $gt = Chalk::IR::Node::GT->new(
        id => 10,
        inputs => [1, 2],
        left_id => 1,
        right_id => 2,
    );
    is($gt->op, 'GT', 'GT node returns correct op');
}

# Test 8: GT node should have left_id and right_id accessors
{
    my $gt = Chalk::IR::Node::GT->new(
        id => 11,
        inputs => [5, 6],
        left_id => 5,
        right_id => 6,
    );
    is($gt->left_id, 5, 'GT node has left_id accessor');
    is($gt->right_id, 6, 'GT node has right_id accessor');
}

# Test 10: LT node should implement op() method
{
    my $lt = Chalk::IR::Node::LT->new(
        id => 12,
        inputs => [7, 8],
        left_id => 7,
        right_id => 8,
    );
    is($lt->op, 'LT', 'LT node returns correct op');
}

# Test 11: EQ node should implement op() method
{
    my $eq = Chalk::IR::Node::EQ->new(
        id => 13,
        inputs => [9, 10],
        left_id => 9,
        right_id => 10,
    );
    is($eq->op, 'EQ', 'EQ node returns correct op');
}

# Test 12: NE node should implement op() method
{
    my $ne = Chalk::IR::Node::NE->new(
        id => 14,
        inputs => [11, 12],
        left_id => 11,
        right_id => 12,
    );
    is($ne->op, 'NE', 'NE node returns correct op');
}

# Test 13: LE node should implement op() method
{
    my $le = Chalk::IR::Node::LE->new(
        id => 15,
        inputs => [13, 14],
        left_id => 13,
        right_id => 14,
    );
    is($le->op, 'LE', 'LE node returns correct op');
}

# Test 14: GE node should implement op() method
{
    my $ge = Chalk::IR::Node::GE->new(
        id => 16,
        inputs => [15, 16],
        left_id => 15,
        right_id => 16,
    );
    is($ge->op, 'GE', 'GE node returns correct op');
}

# Test 15: Polymorphism - calling op() on different comparison nodes
{
    my @nodes = (
        Chalk::IR::Node::GT->new(id => 100, inputs => [1, 2], left_id => 1, right_id => 2),
        Chalk::IR::Node::LT->new(id => 101, inputs => [3, 4], left_id => 3, right_id => 4),
        Chalk::IR::Node::EQ->new(id => 102, inputs => [5, 6], left_id => 5, right_id => 6),
        Chalk::IR::Node::NE->new(id => 103, inputs => [7, 8], left_id => 7, right_id => 8),
        Chalk::IR::Node::LE->new(id => 104, inputs => [9, 10], left_id => 9, right_id => 10),
        Chalk::IR::Node::GE->new(id => 105, inputs => [11, 12], left_id => 11, right_id => 12),
    );

    my @ops = map { $_->op } @nodes;
    is_deeply(\@ops, ['GT', 'LT', 'EQ', 'NE', 'LE', 'GE'],
              'Polymorphic op() calls work for comparison nodes');
}

# Test 16: to_hash() should include attributes for GT
{
    my $gt = Chalk::IR::Node::GT->new(id => 200, inputs => [10, 20], left_id => 10, right_id => 20);
    my $hash = $gt->to_hash();
    is($hash->{attributes}{left_id}, 10, 'GT to_hash() includes left_id');
    is($hash->{attributes}{right_id}, 20, 'GT to_hash() includes right_id');
}

# Test 18: All comparison nodes inherit from Base
{
    my $eq = Chalk::IR::Node::EQ->new(id => 300, inputs => [1, 2], left_id => 1, right_id => 2);
    isa_ok($eq, 'Chalk::IR::Node::Base', 'EQ node');
}

# Test 19-20: Comparison operations have consistent interface
{
    my $ne = Chalk::IR::Node::NE->new(id => 400, inputs => [50, 60], left_id => 50, right_id => 60);
    is($ne->left_id, 50, 'NE has left_id');
    is($ne->right_id, 60, 'NE has right_id');
}

done_testing();
