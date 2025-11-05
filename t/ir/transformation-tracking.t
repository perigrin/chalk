#!/usr/bin/env perl
# ABOUTME: Test transformation tracking in IR nodes via Builder
# ABOUTME: Verify nodes record and expose transformation history correctly
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More;
use Chalk::IR::Builder;

# Test 1: Constant node records transformation
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();
    my $constant = $builder->build_constant_node(42);

    isa_ok($constant, 'Chalk::IR::Node::Constant', 'Constant node created');

    my $chain = $constant->get_transform_chain();
    is(scalar(@$chain), 1, 'Constant has one transformation record');

    my $record = $chain->[0];
    is($record->operation, 'ir_construction', 'Transformation operation is ir_construction');
    is($record->name, 'Builder::build_constant_node', 'Transformation name is correct');
    like($record->context, qr/value=42/, 'Context includes value');
}

# Test 2: Return node records transformation
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();
    my $value = $builder->build_constant_node(10);
    my $return = $builder->build_return_node($value);

    my $chain = $return->get_transform_chain();
    is(scalar(@$chain), 1, 'Return has one transformation record');

    my $record = $chain->[0];
    is($record->operation, 'ir_construction', 'Return transformation operation correct');
    is($record->name, 'Builder::build_return_node', 'Return transformation name correct');
    like($record->context, qr/value_id=/, 'Return context includes value_id');
}

# Test 3: Add node records transformation with both operands
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();
    my $left = $builder->build_constant_node(5);
    my $right = $builder->build_constant_node(3);
    my $add = $builder->build_add_node($left, $right);

    my $chain = $add->get_transform_chain();
    is(scalar(@$chain), 1, 'Add has one transformation record');

    my $record = $chain->[0];
    is($record->operation, 'ir_construction', 'Add transformation operation correct');
    is($record->name, 'Builder::build_add_node', 'Add transformation name correct');
    like($record->context, qr/left_id=/, 'Add context includes left_id');
    like($record->context, qr/right_id=/, 'Add context includes right_id');
}

# Test 4: Start node records transformation
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node('test_function');

    my $chain = $start->get_transform_chain();
    is(scalar(@$chain), 1, 'Start has one transformation record');

    my $record = $chain->[0];
    is($record->operation, 'ir_construction', 'Start transformation operation correct');
    is($record->name, 'Builder::build_start_node', 'Start transformation name correct');
    like($record->context, qr/function=test_function/, 'Start context includes function name');
}

# Test 5: Multiply node records transformation
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();
    my $left = $builder->build_constant_node(4);
    my $right = $builder->build_constant_node(7);
    my $mul = $builder->build_multiply_node($left, $right);

    my $chain = $mul->get_transform_chain();
    is(scalar(@$chain), 1, 'Multiply has one transformation record');

    my $record = $chain->[0];
    is($record->name, 'Builder::build_multiply_node', 'Multiply transformation name correct');
}

# Test 6: Subtract node records transformation
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();
    my $left = $builder->build_constant_node(10);
    my $right = $builder->build_constant_node(3);
    my $sub = $builder->build_sub_node($left, $right);

    my $chain = $sub->get_transform_chain();
    is(scalar(@$chain), 1, 'Subtract has one transformation record');

    my $record = $chain->[0];
    is($record->name, 'Builder::build_sub_node', 'Subtract transformation name correct');
}

# Test 7: Divide node records transformation
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();
    my $left = $builder->build_constant_node(20);
    my $right = $builder->build_constant_node(4);
    my $div = $builder->build_divide_node($left, $right);

    my $chain = $div->get_transform_chain();
    is(scalar(@$chain), 1, 'Divide has one transformation record');

    my $record = $chain->[0];
    is($record->name, 'Builder::build_divide_node', 'Divide transformation name correct');
}

# Test 8: Transform chain is independent for different nodes
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();
    my $const1 = $builder->build_constant_node(1);
    my $const2 = $builder->build_constant_node(2);

    my $chain1 = $const1->get_transform_chain();
    my $chain2 = $const2->get_transform_chain();

    isnt($chain1, $chain2, 'Different nodes have different transform chains');
    is(scalar(@$chain1), 1, 'First constant has one record');
    is(scalar(@$chain2), 1, 'Second constant has one record');
}

# Test 9: debug_transform_chain returns formatted string
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();
    my $constant = $builder->build_constant_node(99);

    my $debug_output = $constant->debug_transform_chain();

    like($debug_output, qr/Transformation history/, 'Debug output has header');
    like($debug_output, qr/ir_construction/, 'Debug output shows operation');
    like($debug_output, qr/Builder::build_constant_node/, 'Debug output shows name');
}

# Test 10: get_transform_chain returns copy (not modifiable reference)
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();
    my $constant = $builder->build_constant_node(50);

    my $chain1 = $constant->get_transform_chain();
    my $chain2 = $constant->get_transform_chain();

    isnt($chain1, $chain2, 'get_transform_chain returns a copy');
    is(scalar(@$chain1), scalar(@$chain2), 'Both copies have same number of records');
}

done_testing();
