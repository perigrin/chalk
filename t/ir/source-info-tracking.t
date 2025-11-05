#!/usr/bin/env perl
# ABOUTME: Test source_info tracking in IR nodes via Builder
# ABOUTME: Verify nodes store and expose source location information correctly
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More;
use Chalk::IR::Builder;
use Chalk::IR::SourceInfo;

# Test 1: Create constant node with source_info
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path  => 'test.chalk',
        start_line => 5,
        start_col  => 10,
        end_line   => 5,
        end_col    => 15,
        start_pos  => 50,
        end_pos    => 55,
    );

    my $constant = $builder->build_constant_node(42, 'Int', $source_info);

    isa_ok($constant, 'Chalk::IR::Node::Constant', 'Constant node created');
    is($constant->source_info, $source_info, 'Constant node stores source_info');
    is($constant->source_info->file_path, 'test.chalk', 'Source info has correct file path');
    is($constant->source_info->start_line, 5, 'Source info has correct start line');
}

# Test 2: Create constant node without source_info (should default to undef)
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();

    my $constant = $builder->build_constant_node(42);

    isa_ok($constant, 'Chalk::IR::Node::Constant', 'Constant node created without source_info');
    is($constant->source_info, undef, 'Constant node has undef source_info by default');
}

# Test 3: Create add node with source_info
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();

    my $left = $builder->build_constant_node(5);
    my $right = $builder->build_constant_node(3);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path  => 'add.chalk',
        start_line => 10,
        start_col  => 5,
        end_line   => 10,
        end_col    => 10,
        start_pos  => 100,
        end_pos    => 105,
    );

    my $add = $builder->build_add_node($left, $right, $source_info);

    isa_ok($add, 'Chalk::IR::Node::Add', 'Add node created');
    is($add->source_info, $source_info, 'Add node stores source_info');
    is($add->source_info->start_line, 10, 'Add source info has correct line');
}

# Test 4: Create return node with source_info
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();

    my $value = $builder->build_constant_node(42);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path  => 'return.chalk',
        start_line => 20,
        start_col  => 1,
        end_line   => 20,
        end_col    => 10,
        start_pos  => 200,
        end_pos    => 209,
    );

    my $return = $builder->build_return_node($value, undef, $source_info);

    isa_ok($return, 'Chalk::IR::Node::Return', 'Return node created');
    is($return->source_info, $source_info, 'Return node stores source_info');
    is($return->source_info->file_path, 'return.chalk', 'Return source info has correct file');
}

# Test 5: Different nodes can have different source_info
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();

    my $source_info1 = Chalk::IR::SourceInfo->new(
        file_path  => 'test.chalk',
        start_line => 1,
        start_col  => 1,
        end_line   => 1,
        end_col    => 5,
        start_pos  => 0,
        end_pos    => 4,
    );

    my $source_info2 = Chalk::IR::SourceInfo->new(
        file_path  => 'test.chalk',
        start_line => 2,
        start_col  => 1,
        end_line   => 2,
        end_col    => 5,
        start_pos  => 10,
        end_pos    => 14,
    );

    my $const1 = $builder->build_constant_node(10, 'Int', $source_info1);
    my $const2 = $builder->build_constant_node(20, 'Int', $source_info2);

    isnt($const1->source_info, $const2->source_info, 'Different nodes have different source_info');
    is($const1->source_info->start_line, 1, 'First node has line 1');
    is($const2->source_info->start_line, 2, 'Second node has line 2');
}

done_testing();
