#!/usr/bin/env perl
# ABOUTME: Test ValidationContext class for semantic validation at IR build time
# ABOUTME: Verify undefined variable detection, type validation, and helpful error messages
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More;
use Chalk::IR::Builder;
use Chalk::IR::SourceInfo;
use Chalk::Error::CompilationError;

# Test 1: Undefined variable detection with build_load_node
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    # Define one variable
    my $x = $builder->build_constant_node(5);
    $builder->set_context(
        Chalk::IR::Context->extend_context(
            $builder->context,
            "lexical:x",
            $x
        )
    );

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 5, start_col => 10,
        end_line => 5, end_col => 12,
        start_pos => 50, end_pos => 52
    );

    # Try to load undefined variable
    eval {
        my $node = $builder->build_load_node('y', $source_info);
    };

    like($@, qr/Undefined variable/, 'Detects undefined variable');
    like($@, qr/\$y/, 'Error message includes variable name');
    like($@, qr/test\.chalk:5:10/, 'Includes source location');
    # Note: Hints are stored in CompilationError object but don't appear in stringified form
    isa_ok($@, 'Chalk::Error::CompilationError', 'Error is CompilationError object');
}

# Test 2: Variable validation passes when variable exists
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $x = $builder->build_constant_node(42);
    $builder->set_context(
        Chalk::IR::Context->extend_context(
            $builder->context,
            "lexical:x",
            $x
        )
    );

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 1, start_col => 1,
        end_line => 1, end_col => 2,
        start_pos => 0, end_pos => 1
    );

    # Should succeed
    my $node = $builder->build_load_node('x', $source_info);
    is($node, $x, 'Returns correct node for defined variable');
}

# Test 3: Type validation rejects array in addition
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $array = $builder->build_array_value_node([]);
    my $num = $builder->build_constant_node(5);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 3, start_col => 10,
        end_line => 3, end_col => 20,
        start_pos => 30, end_pos => 40
    );

    eval {
        my $result = $builder->build_add_node($array, $num, $source_info);
    };

    like($@, qr/Cannot use.*operator.*array/i, 'Rejects array in arithmetic');
    # Note: Hints are stored in CompilationError object but don't appear in stringified form
    isa_ok($@, 'Chalk::Error::CompilationError', 'Error is CompilationError with hints');
}

# Test 4: Type validation allows valid number addition
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $left = $builder->build_constant_node(5);
    my $right = $builder->build_constant_node(3);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 1, start_col => 1,
        end_line => 1, end_col => 5,
        start_pos => 0, end_pos => 4
    );

    # Should succeed
    my $result = $builder->build_add_node($left, $right, $source_info);
    isa_ok($result, 'Chalk::IR::Node::Add', 'Valid addition creates Add node');
}

# Test 5: Type validation without source_info is lenient
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $array = $builder->build_array_value_node([]);
    my $num = $builder->build_constant_node(5);

    # Without source_info, validation is skipped
    my $result;
    eval {
        $result = $builder->build_add_node($array, $num);
    };

    # Should not die (backward compatibility)
    is($@, '', 'No validation without source_info');
    isa_ok($result, 'Chalk::IR::Node::Add', 'Still creates Add node');
}

# Test 6: Type inference for constants
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $int_const = $builder->build_constant_node(42, 'Int');
    my $type = $builder->_infer_type_from_node($int_const);
    is($type, 'Int', 'Infers Int type from constant');
}

# Test 7: Type inference for arrays
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $array = $builder->build_array_value_node([]);
    my $type = $builder->_infer_type_from_node($array);
    is($type, 'Array', 'Infers Array type from ArrayValue node');
}

# Test 8: Type inference for arithmetic operations
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $left = $builder->build_constant_node(5);
    my $right = $builder->build_constant_node(3);
    my $add = $builder->build_add_node($left, $right);

    my $type = $builder->_infer_type_from_node($add);
    is($type, 'Num', 'Add operation inferred as Num type');
}

# Test 9: Type validation rejects hash in arithmetic
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $hash = $builder->build_hash_value_node({});
    my $num = $builder->build_constant_node(5);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 2, start_col => 5,
        end_line => 2, end_col => 15,
        start_pos => 20, end_pos => 30
    );

    eval {
        my $result = $builder->build_add_node($num, $hash, $source_info);
    };

    like($@, qr/Cannot use.*operator.*hash/i, 'Rejects hash in arithmetic');
}

# Test 10: Error message includes source location
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'example.chalk',
        start_line => 10, start_col => 15,
        end_line => 10, end_col => 17,
        start_pos => 100, end_pos => 102
    );

    eval {
        my $node = $builder->build_load_node('undefined', $source_info);
    };

    my $error = $@;
    like($error, qr/example\.chalk/, 'Error includes filename');
    like($error, qr/10/, 'Error includes line number');
    like($error, qr/15/, 'Error includes column number');
}

done_testing();
