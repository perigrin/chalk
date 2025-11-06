#!/usr/bin/env perl
# ABOUTME: Test P1 context validation features (multiply/subtract/divide, function arity, field access)
# ABOUTME: Verify all arithmetic operations, function call validation, and class field validation
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More;
use Chalk::IR::Builder;
use Chalk::IR::SourceInfo;
use Chalk::Error::CompilationError;

# Test 1: Type validation for multiply operation
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $array = $builder->build_array_value_node([]);
    my $num = $builder->build_constant_node(5);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 1, start_col => 1,
        end_line => 1, end_col => 10,
        start_pos => 0, end_pos => 9
    );

    eval {
        my $result = $builder->build_multiply_node($array, $num, $source_info);
    };

    like($@, qr/Cannot use.*Multiply.*operator.*array/i, 'Multiply rejects array operand');
    like($@, qr/hint:/i, 'Provides hints for multiply error');
}

# Test 2: Type validation for subtract operation
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $hash = $builder->build_hash_value_node({});
    my $num = $builder->build_constant_node(10);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 2, start_col => 1,
        end_line => 2, end_col => 10,
        start_pos => 20, end_pos => 29
    );

    eval {
        my $result = $builder->build_sub_node($num, $hash, $source_info);
    };

    like($@, qr/Cannot use.*Subtract.*operator.*hash/i, 'Subtract rejects hash operand');
}

# Test 3: Type validation for divide operation
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $array = $builder->build_array_value_node([]);
    my $num = $builder->build_constant_node(2);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 3, start_col => 5,
        end_line => 3, end_col => 15,
        start_pos => 40, end_pos => 50
    );

    eval {
        my $result = $builder->build_divide_node($num, $array, $source_info);
    };

    like($@, qr/Cannot use.*Divide.*operator.*array/i, 'Divide rejects array operand');
}

# Test 4: Valid multiply operation
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $left = $builder->build_constant_node(4);
    my $right = $builder->build_constant_node(5);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 1, start_col => 1,
        end_line => 1, end_col => 5,
        start_pos => 0, end_pos => 4
    );

    my $result = $builder->build_multiply_node($left, $right, $source_info);
    isa_ok($result, 'Chalk::IR::Node::Multiply', 'Valid multiply creates Multiply node');
}

# Test 5: Valid subtract operation
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $left = $builder->build_constant_node(10);
    my $right = $builder->build_constant_node(3);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 1, start_col => 1,
        end_line => 1, end_col => 5,
        start_pos => 0, end_pos => 4
    );

    my $result = $builder->build_sub_node($left, $right, $source_info);
    isa_ok($result, 'Chalk::IR::Node::Subtract', 'Valid subtract creates Subtract node');
}

# Test 6: Valid divide operation
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $left = $builder->build_constant_node(20);
    my $right = $builder->build_constant_node(4);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 1, start_col => 1,
        end_line => 1, end_col => 5,
        start_pos => 0, end_pos => 4
    );

    my $result = $builder->build_divide_node($left, $right, $source_info);
    isa_ok($result, 'Chalk::IR::Node::Divide', 'Valid divide creates Divide node');
}

# Test 7: Function call arity validation - too few arguments
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    # Register a function with arity 2
    my $func_def = { arity => 2 };
    $builder->set_context(
        Chalk::IR::Context->extend_context(
            $builder->context,
            "function:add_nums",
            $func_def
        )
    );

    my $arg1 = $builder->build_constant_node(5);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 5, start_col => 1,
        end_line => 5, end_col => 20,
        start_pos => 50, end_pos => 69
    );

    eval {
        my $call = $builder->build_call_node('add_nums', $source_info, $arg1);
    };

    like($@, qr/expects 2 arguments, got 1/, 'Detects too few arguments');
    like($@, qr/missing.*1.*argument/i, 'Hints about missing arguments');
}

# Test 8: Function call arity validation - too many arguments
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    # Register a function with arity 1
    my $func_def = { arity => 1 };
    $builder->set_context(
        Chalk::IR::Context->extend_context(
            $builder->context,
            "function:double",
            $func_def
        )
    );

    my $arg1 = $builder->build_constant_node(5);
    my $arg2 = $builder->build_constant_node(10);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 6, start_col => 1,
        end_line => 6, end_col => 20,
        start_pos => 70, end_pos => 89
    );

    eval {
        my $call = $builder->build_call_node('double', $source_info, $arg1, $arg2);
    };

    like($@, qr/expects 1 argument, got 2/, 'Detects too many arguments');
    like($@, qr/too many.*1.*argument/i, 'Hints about excess arguments');
}

# Test 9: Function call arity validation - correct arity
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    # Register a function with arity 2
    my $func_def = { arity => 2 };
    $builder->set_context(
        Chalk::IR::Context->extend_context(
            $builder->context,
            "function:add",
            $func_def
        )
    );

    my $arg1 = $builder->build_constant_node(5);
    my $arg2 = $builder->build_constant_node(3);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 1, start_col => 1,
        end_line => 1, end_col => 10,
        start_pos => 0, end_pos => 9
    );

    my $call = $builder->build_call_node('add', $source_info, $arg1, $arg2);
    isa_ok($call, 'Chalk::IR::Node', 'Valid function call creates Call node');
    is($call->op, 'Call', 'Node has Call operation');
}

# Test 10: Function call without registered signature (should not validate)
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $arg1 = $builder->build_constant_node(5);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 1, start_col => 1,
        end_line => 1, end_col => 10,
        start_pos => 0, end_pos => 9
    );

    # Should not die even though arity might be wrong
    my $call = $builder->build_call_node('unknown_func', $source_info, $arg1);
    isa_ok($call, 'Chalk::IR::Node', 'Unknown function call still creates node');
}

# Test 11: Class field validation - invalid field
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    # Register a class definition
    my $class_def = { fields => ['x', 'y'] };
    $builder->set_context(
        Chalk::IR::Context->extend_context(
            $builder->context,
            "class:Point",
            $class_def
        )
    );

    # Create an object of type Point
    my $obj = $builder->build_new_node('Point', {});

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 7, start_col => 10,
        end_line => 7, end_col => 12,
        start_pos => 100, end_pos => 102
    );

    eval {
        my $access = $builder->build_field_access_node($obj, 'z', $source_info);
    };

    like($@, qr/has no field.*z/i, 'Detects invalid field access');
    like($@, qr/Valid fields:.*x.*y/i, 'Lists valid fields');
}

# Test 12: Class field validation - valid field
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    # Register a class definition
    my $class_def = { fields => ['x', 'y'] };
    $builder->set_context(
        Chalk::IR::Context->extend_context(
            $builder->context,
            "class:Point",
            $class_def
        )
    );

    # Create an object of type Point
    my $obj = $builder->build_new_node('Point', {});

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 1, start_col => 1,
        end_line => 1, end_col => 5,
        start_pos => 0, end_pos => 4
    );

    my $access = $builder->build_field_access_node($obj, 'x', $source_info);
    isa_ok($access, 'Chalk::IR::Node', 'Valid field access creates node');
    is($access->op, 'FieldAccess', 'Node has FieldAccess operation');
}

# Test 13: Backward compatibility - operations without source_info
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $array = $builder->build_array_value_node([]);
    my $num = $builder->build_constant_node(5);

    # Should not die without source_info (backward compat)
    my $result = $builder->build_multiply_node($array, $num);
    isa_ok($result, 'Chalk::IR::Node::Multiply', 'Backward compat: no validation without source_info');
}

done_testing();
