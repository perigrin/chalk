# ABOUTME: Tests for polymorphic logical IR node subclasses
# ABOUTME: Verifies And, Or, and DefinedOr nodes
use lib 'lib';
use 5.42.0;
use experimental qw(class);
use lib 'lib';
use Test::More;

plan tests => 17;

# Test 1-3: Logical node subclasses should be loadable
use_ok('Chalk::IR::Node::And');
use_ok('Chalk::IR::Node::Or');
use_ok('Chalk::IR::Node::DefinedOr');

# Test 4: And node should implement op() method
{
    my $and = Chalk::IR::Node::And->new(
        id => 10,
        inputs => [1, 2],
        left_id => 1,
        right_id => 2,
    );
    is($and->op, 'And', 'And node returns correct op');
}

# Test 5-6: And node should have left_id and right_id accessors
{
    my $and = Chalk::IR::Node::And->new(
        id => 11,
        inputs => [5, 6],
        left_id => 5,
        right_id => 6,
    );
    is($and->left_id, 5, 'And node has left_id accessor');
    is($and->right_id, 6, 'And node has right_id accessor');
}

# Test 7: Or node should implement op() method
{
    my $or = Chalk::IR::Node::Or->new(
        id => 12,
        inputs => [7, 8],
        left_id => 7,
        right_id => 8,
    );
    is($or->op, 'Or', 'Or node returns correct op');
}

# Test 8-9: Or node should have left_id and right_id accessors
{
    my $or = Chalk::IR::Node::Or->new(
        id => 13,
        inputs => [9, 10],
        left_id => 9,
        right_id => 10,
    );
    is($or->left_id, 9, 'Or node has left_id accessor');
    is($or->right_id, 10, 'Or node has right_id accessor');
}

# Test 10: DefinedOr node should implement op() method
{
    my $dor = Chalk::IR::Node::DefinedOr->new(
        id => 14,
        inputs => [11, 12],
        left_id => 11,
        right_id => 12,
    );
    is($dor->op, 'DefinedOr', 'DefinedOr node returns correct op');
}

# Test 11-12: DefinedOr node should have left_id and right_id accessors
{
    my $dor = Chalk::IR::Node::DefinedOr->new(
        id => 15,
        inputs => [13, 14],
        left_id => 13,
        right_id => 14,
    );
    is($dor->left_id, 13, 'DefinedOr node has left_id accessor');
    is($dor->right_id, 14, 'DefinedOr node has right_id accessor');
}

# Test 13: Polymorphism - calling op() on different logical nodes
{
    my @nodes = (
        Chalk::IR::Node::And->new(id => 100, inputs => [1, 2], left_id => 1, right_id => 2),
        Chalk::IR::Node::Or->new(id => 101, inputs => [3, 4], left_id => 3, right_id => 4),
        Chalk::IR::Node::DefinedOr->new(id => 102, inputs => [5, 6], left_id => 5, right_id => 6),
    );

    my @ops = map { $_->op } @nodes;
    is_deeply(\@ops, ['And', 'Or', 'DefinedOr'],
              'Polymorphic op() calls work for logical nodes');
}

# Test 14-15: to_hash() should include attributes for And
{
    my $and = Chalk::IR::Node::And->new(id => 200, inputs => [10, 20], left_id => 10, right_id => 20);
    my $hash = $and->to_hash();
    is($hash->{attributes}{left_id}, 10, 'And to_hash() includes left_id');
    is($hash->{attributes}{right_id}, 20, 'And to_hash() includes right_id');
}

# Test 16: All logical nodes inherit from Base
TODO: {
    local $TODO = 'Issue #198: IR node inheritance inconsistency';
    my $and = Chalk::IR::Node::And->new(id => 300, inputs => [1, 2], left_id => 1, right_id => 2);
    isa_ok($and, 'Chalk::IR::Node::Base', 'And node');
}

# Test 17: Binary operations have consistent interface
{
    my $or = Chalk::IR::Node::Or->new(id => 400, inputs => [50, 60], left_id => 50, right_id => 60);
    is($or->left_id, 50, 'Or has left_id');
}

done_testing();
