#!/usr/bin/env perl
# ABOUTME: Test P2 context validation features (loop tracking, scope validation, references, Region)
# ABOUTME: Verify loop variable tracking, reference target validation, and enhanced control flow checks
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More;
use Chalk::IR::Builder;
use Chalk::IR::SourceInfo;
use Chalk::Error::CompilationError;

# Test 1: Loop variable validation - variable modified in loop without pre-loop definition
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    $builder->begin_loop_tracking();

    my $value = $builder->build_constant_node(10);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 5, start_col => 5,
        end_line => 5, end_col => 15,
        start_pos => 50, end_pos => 60
    );

    eval {
        # Try to modify a variable inside loop that wasn't defined before loop
        my $stored = $builder->build_store_node('counter', $value, undef, $source_info);
    };

    like($@, qr/modified in loop but not defined before loop/i, 'Catches undefined loop variable');
    like($@, qr/Declare the variable.*before the loop/i, 'Hints about pre-loop declaration');
}

# Test 2: Loop variable validation - properly initialized loop variable
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    # Define variable before loop
    my $initial = $builder->build_constant_node(0);
    $builder->build_store_node('counter', $initial);

    $builder->begin_loop_tracking();

    my $value = $builder->build_constant_node(10);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 5, start_col => 5,
        end_line => 5, end_col => 15,
        start_pos => 50, end_pos => 60
    );

    # Should succeed - variable exists before loop
    my $stored = $builder->build_store_node('counter', $value, undef, $source_info);
    ok(defined $stored, 'Accepts properly initialized loop variable');
}

# Test 3: Reference target validation - undefined variable
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 3, start_col => 10,
        end_line => 3, end_col => 15,
        start_pos => 30, end_pos => 35
    );

    eval {
        my $ref = $builder->build_scalar_ref_node('undefined_var', $source_info);
    };

    like($@, qr/Cannot create reference to undefined/i, 'Rejects reference to undefined variable');
    like($@, qr/undefined_var/i, 'Error message includes variable name');
    like($@, qr/Declare the variable/i, 'Provides declaration hint');
}

# Test 4: Reference target validation - valid reference
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    # Define a variable
    my $value = $builder->build_constant_node(42);
    $builder->build_store_node('target', $value);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 2, start_col => 1,
        end_line => 2, end_col => 10,
        start_pos => 20, end_pos => 29
    );

    # Should succeed
    my $ref = $builder->build_scalar_ref_node('target', $source_info);
    isa_ok($ref, 'Chalk::IR::Node::Reference', 'Valid reference creates Reference node');
}

# Test 5: Region validation - undefined control node
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 4, start_col => 1,
        end_line => 4, end_col => 10,
        start_pos => 40, end_pos => 49
    );

    eval {
        # Try to create Region with non-existent control node ID
        my $region = $builder->build_region_node($source_info, 'nonexistent_node_123');
    };

    like($@, qr/undefined control node/i, 'Catches undefined control node');
    like($@, qr/nonexistent_node_123/i, 'Error includes node ID');
}

# Test 6: Region validation - merging Start with other control
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();

    my $const = $builder->build_constant_node(5);

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 5, start_col => 1,
        end_line => 5, end_col => 10,
        start_pos => 50, end_pos => 59
    );

    eval {
        # Try to merge Start node with another control flow (invalid)
        my $region = $builder->build_region_node($source_info, $start->id, $const->id);
    };

    like($@, qr/Cannot merge Start node/i, 'Rejects merging Start with other control');
    like($@, qr/unique.*entry point/i, 'Explains Start should be unique entry');
}

# Test 7: Region validation - valid Region without validation (backward compat)
{
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();

    # Create some control nodes
    my $cond = $builder->build_constant_node(1);
    my $if_node = $builder->build_if_node($cond);
    my $if_true = $builder->build_proj_node($if_node, 0, 'IfTrue');
    my $if_false = $builder->build_proj_node($if_node, 1, 'IfFalse');

    # Without source_info, should not validate (backward compat)
    my $region = $builder->build_region_node(undef, $if_true->id, $if_false->id);
    isa_ok($region, 'Chalk::IR::Node::Region', 'Backward compat: Region without validation');
}

# Test 8: Loop tracking depth
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    is($builder->current_loop_depth(), 0, 'Initial loop depth is 0');

    $builder->begin_loop_tracking();
    is($builder->current_loop_depth(), 1, 'Loop depth increments');

    $builder->begin_loop_tracking();
    is($builder->current_loop_depth(), 2, 'Nested loop depth increments');

    $builder->end_loop_tracking();
    is($builder->current_loop_depth(), 1, 'Loop depth decrements');

    $builder->end_loop_tracking();
    is($builder->current_loop_depth(), 0, 'Back to depth 0');
}

# Test 9: Multiple loop variables
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    # Define variables before loop
    my $i_init = $builder->build_constant_node(0);
    my $sum_init = $builder->build_constant_node(0);
    $builder->build_store_node('i', $i_init);
    $builder->build_store_node('sum', $sum_init);

    $builder->begin_loop_tracking();

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 10, start_col => 5,
        end_line => 10, end_col => 15,
        start_pos => 100, end_pos => 110
    );

    # Both variables should validate successfully
    my $new_i = $builder->build_constant_node(1);
    my $new_sum = $builder->build_constant_node(10);

    my $stored_i = $builder->build_store_node('i', $new_i, undef, $source_info);
    my $stored_sum = $builder->build_store_node('sum', $new_sum, undef, $source_info);

    ok(defined $stored_i && defined $stored_sum, 'Multiple loop variables validate');
}

# Test 10: Reference without source_info (backward compat)
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $value = $builder->build_constant_node(99);
    $builder->build_store_node('var', $value);

    # Without source_info, old error handling applies
    my $ref = $builder->build_scalar_ref_node('var');
    isa_ok($ref, 'Chalk::IR::Node::Reference', 'Reference backward compat works');
}

# Test 11: Reference to undefined variable without source_info
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    eval {
        # Old error message (die, not CompilationError)
        my $ref = $builder->build_scalar_ref_node('nonexistent');
    };

    like($@, qr/undefined variable/i, 'Old error handling still works');
}

# Test 12: Scope boundary validation (placeholder test)
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 1, start_col => 1,
        end_line => 1, end_col => 5,
        start_pos => 0, end_pos => 4
    );

    # Scope validation is currently a placeholder that always succeeds
    my $type_lattice = Chalk::Grammar::Chalk::TypeLattice->new();
    my $validator = Chalk::IR::ValidationContext->new(
        context => $builder->context,
        graph => $builder->graph,
        type_lattice => $type_lattice
    );

    my $result = $validator->validate_scope_boundary('var', 'function', $source_info);
    is($result, 1, 'Scope boundary validation placeholder succeeds');
}

# Test 13: Integration - Complex scenario with loops and references
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    # Define variable outside loop
    my $initial = $builder->build_constant_node(0);
    $builder->build_store_node('total', $initial);

    # Create reference to it
    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 8, start_col => 10,
        end_line => 8, end_col => 17,
        start_pos => 80, end_pos => 87
    );

    my $ref = $builder->build_scalar_ref_node('total', $source_info);
    ok(defined $ref, 'Reference to pre-loop variable succeeds');

    # Enter loop
    $builder->begin_loop_tracking();

    # Modify variable in loop (should validate)
    my $new_val = $builder->build_constant_node(100);
    my $stored = $builder->build_store_node('total', $new_val, undef, $source_info);
    ok(defined $stored, 'Loop modification of pre-loop variable succeeds');

    $builder->end_loop_tracking();
}

done_testing();
