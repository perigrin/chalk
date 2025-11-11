# ABOUTME: Tests for polymorphic control flow IR node subclasses
# ABOUTME: Verifies If, Proj, Region, Phi, and Loop control flow nodes
use lib 'lib';
use 5.42.0;
use experimental qw(class);
use lib 'lib';
use Test::More;

plan tests => 20;

# Test 1-5: Control flow node subclasses should be loadable
use_ok('Chalk::IR::Node::If');
use_ok('Chalk::IR::Node::Proj');
use_ok('Chalk::IR::Node::Region');
use_ok('Chalk::IR::Node::Phi');
use_ok('Chalk::IR::Node::Loop');

# Test 6: If node should implement op() method
{
    my $if_node = Chalk::IR::Node::If->new(
        id => 10,
        inputs => [1, 2],
        condition_id => 2,
    );
    is($if_node->op, 'If', 'If node returns correct op');
}

# Test 7: If node should have condition_id accessor
{
    my $if_node = Chalk::IR::Node::If->new(
        id => 11,
        inputs => [3, 4],
        condition_id => 4,
    );
    is($if_node->condition_id, 4, 'If node has condition_id accessor');
}

# Test 8: Proj node should implement op() method
{
    my $proj = Chalk::IR::Node::Proj->new(
        id => 12,
        inputs => [5],
        index => 0,
        label => 'IfTrue',
    );
    is($proj->op, 'Proj', 'Proj node returns correct op');
}

# Test 9-10: Proj node should have index and label accessors
{
    my $proj = Chalk::IR::Node::Proj->new(
        id => 13,
        inputs => [6],
        index => 1,
        label => 'IfFalse',
    );
    is($proj->index, 1, 'Proj node has index accessor');
    is($proj->label, 'IfFalse', 'Proj node has label accessor');
}

# Test 11: Region node should implement op() method
{
    my $region = Chalk::IR::Node::Region->new(
        id => 14,
        inputs => [7, 8],
    );
    is($region->op, 'Region', 'Region node returns correct op');
}

# Test 12: Phi node should implement op() method
{
    my $phi = Chalk::IR::Node::Phi->new(
        id => 15,
        inputs => [9, 10, 11],
        region_id => 9,
    );
    is($phi->op, 'Phi', 'Phi node returns correct op');
}

# Test 13: Loop node should implement op() method
{
    my $loop = Chalk::IR::Node::Loop->new(
        id => 16,
        inputs => [12],
    );
    is($loop->op, 'Loop', 'Loop node returns correct op');
}

# Test 14: Polymorphism - calling op() on different control flow nodes
{
    my @nodes = (
        Chalk::IR::Node::If->new(id => 100, inputs => [1, 2], condition_id => 2),
        Chalk::IR::Node::Proj->new(id => 101, inputs => [3], index => 0, label => 'Test'),
        Chalk::IR::Node::Region->new(id => 102, inputs => [4, 5]),
        Chalk::IR::Node::Phi->new(id => 103, inputs => [6, 7, 8], region_id => 6),
        Chalk::IR::Node::Loop->new(id => 104, inputs => [9]),
    );

    my @ops = map { $_->op } @nodes;
    is_deeply(\@ops, ['If', 'Proj', 'Region', 'Phi', 'Loop'],
              'Polymorphic op() calls work for control flow nodes');
}

# Test 15: to_hash() should include attributes for If
{
    my $if_node = Chalk::IR::Node::If->new(id => 200, inputs => [10, 20], condition_id => 20);
    my $hash = $if_node->to_hash();
    is($hash->{attributes}{condition_id}, 20, 'If to_hash() includes condition_id');
}

# Test 16-17: to_hash() should include attributes for Proj
{
    my $proj = Chalk::IR::Node::Proj->new(id => 201, inputs => [30], index => 1, label => 'Branch');
    my $hash = $proj->to_hash();
    is($hash->{attributes}{index}, 1, 'Proj to_hash() includes index');
    is($hash->{attributes}{label}, 'Branch', 'Proj to_hash() includes label');
}

# Test 18: All control flow nodes inherit from Base
{
    my $region = Chalk::IR::Node::Region->new(id => 300, inputs => [1, 2]);
    isa_ok($region, 'Chalk::IR::Node::Base', 'Region node');
}

# Test 19-20: Control flow nodes can have variable input counts
{
    my $region3 = Chalk::IR::Node::Region->new(id => 400, inputs => [50, 60, 70]);
    is(scalar @{$region3->inputs}, 3, 'Region can have 3 inputs');

    my $phi4 = Chalk::IR::Node::Phi->new(id => 401, inputs => [80, 90, 100, 110], region_id => 80);
    is(scalar @{$phi4->inputs}, 4, 'Phi can have 4 inputs');
}

done_testing();
