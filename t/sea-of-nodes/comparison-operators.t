# ABOUTME: Test that comparison operators (>=, <=, !=) use correct IR nodes
# ABOUTME: Tests builder methods for GE, LE, NE nodes and semantic actions
use lib 'lib';
use 5.42.0;
use experimental qw(class);
use lib 'lib';
use Test::More;

plan tests => 14;

# Test 1-3: Builder can create GE/LE/NE comparison nodes
{
    use_ok('Chalk::IR::Builder');
    use_ok('Chalk::IR::Node::GE');
    use_ok('Chalk::IR::Node::LE');
}

# Test 4: IR::Builder should have build_greater_or_equal_node method
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $left = $builder->build_constant_node(5);
    my $right = $builder->build_constant_node(3);

    my $ge_node = $builder->build_greater_or_equal_node($left, $right);
    ok($ge_node, 'build_greater_or_equal_node returns a node');
    is($ge_node->op, 'GE', 'Node op is GE');
    is($ge_node->left_id, $left->id, 'GE node has correct left_id');
    is($ge_node->right_id, $right->id, 'GE node has correct right_id');
}

# Test 8: IR::Builder should have build_less_or_equal_node method
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $left = $builder->build_constant_node(2);
    my $right = $builder->build_constant_node(7);

    my $le_node = $builder->build_less_or_equal_node($left, $right);
    ok($le_node, 'build_less_or_equal_node returns a node');
    is($le_node->op, 'LE', 'Node op is LE');
    is($le_node->left_id, $left->id, 'LE node has correct left_id');
    is($le_node->right_id, $right->id, 'LE node has correct right_id');
}

# Test 12: IR::Builder should have build_not_equal_node method
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $left = $builder->build_constant_node(10);
    my $right = $builder->build_constant_node(20);

    my $ne_node = $builder->build_not_equal_node($left, $right);
    ok($ne_node, 'build_not_equal_node returns a node');
    is($ne_node->op, 'NE', 'Node op is NE');
    is($ne_node->left_id, $left->id, 'NE node has correct left_id');
}

done_testing();
