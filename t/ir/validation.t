#!/usr/bin/env perl
# ABOUTME: Test IR node validation for catching construction errors
# ABOUTME: Verify nodes reject invalid inputs and provide helpful error messages
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More;
use Chalk::IR::Builder;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Constant;

# Test 1: Create valid Add node (baseline)
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();
    my $left = $builder->build_constant_node(5);
    my $right = $builder->build_constant_node(3);

    my $add = $builder->build_add_node($left, $right);

    isa_ok($add, 'Chalk::IR::Node::Add', 'Valid Add node created');
    is($add->left_id, $left->id, 'Left operand ID correct');
    is($add->right_id, $right->id, 'Right operand ID correct');
}

# Test 2: Add node with undefined left operand should die
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();
    my $right = $builder->build_constant_node(3);

    eval {
        my $add = $builder->build_add_node(undef, $right);
    };
    like($@, qr/undefined|undef|invalid/i, 'Rejects undefined left operand');
}

# Test 3: Add node with undefined right operand should die
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();
    my $left = $builder->build_constant_node(5);

    eval {
        my $add = $builder->build_add_node($left, undef);
    };
    like($@, qr/undefined|undef|invalid/i, 'Rejects undefined right operand');
}

# Test 4: Add node with non-node left operand should die
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();
    my $right = $builder->build_constant_node(3);

    eval {
        my $add = $builder->build_add_node("not a node", $right);
    };
    like($@, qr/node|invalid|type/i, 'Rejects non-node left operand');
}

# Test 5: Add node with non-node right operand should die
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();
    my $left = $builder->build_constant_node(5);

    eval {
        my $add = $builder->build_add_node($left, 42);
    };
    like($@, qr/node|invalid|type/i, 'Rejects non-node right operand');
}

# Test 6: Constant node with undefined value is allowed (for implicit returns)
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();

    my $const;
    eval {
        $const = $builder->build_constant_node(undef);
    };
    ok(!$@, 'Allows undefined constant value (needed for implicit returns)');
    isa_ok($const, 'Chalk::IR::Node::Constant', 'Created undef constant node');
}

# Test 7: Return node with undefined value should die
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();

    eval {
        my $ret = $builder->build_return_node(undef);
    };
    like($@, qr/node|value|undefined|undef/i, 'Rejects undefined return value');
}

# Test 8: Return node with non-node value should die
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();

    eval {
        my $ret = $builder->build_return_node("not a node");
    };
    like($@, qr/node|value|invalid|type/i, 'Rejects non-node return value');
}

done_testing();
