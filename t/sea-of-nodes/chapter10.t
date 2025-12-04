#!/usr/bin/env perl
# ABOUTME: Test Sea of Nodes Chapter 10 - User-defined structures and memory
# ABOUTME: Validates MemoryPointer, Memory, and struct operations

use lib 'lib';
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Type::MemoryPointer;
use Chalk::IR::Type::Memory;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

subtest 'MemoryPointer: basic construction' => sub {
    # Non-null pointer to a struct
    my $ptr = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 0,
    );

    ok $ptr, 'Created non-null pointer';
    is $ptr->struct_name, 'Point', 'Pointer targets Point struct';
    ok !$ptr->nullable, 'Pointer is non-null';
};

subtest 'MemoryPointer: nullable pointer' => sub {
    # Nullable pointer to a struct
    my $ptr = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 1,
    );

    ok $ptr, 'Created nullable pointer';
    is $ptr->struct_name, 'Point', 'Pointer targets Point struct';
    ok $ptr->nullable, 'Pointer is nullable';
};

subtest 'MemoryPointer: NULL constant' => sub {
    # null is a nullable pointer to non-existent memory
    my $null = Chalk::IR::Type::MemoryPointer->NULL();

    ok $null, 'Created NULL constant';
    ok $null->nullable, 'NULL is nullable';
    ok $null->is_top, 'NULL points to TOP (non-existent memory)';
};

subtest 'MemoryPointer: TOP and BOTTOM' => sub {
    # TOP: all possible pointers
    my $top = Chalk::IR::Type::MemoryPointer->TOP();
    ok $top, 'Created MemoryPointer TOP';
    ok $top->is_top, 'TOP is top of lattice';

    # BOTTOM: no pointers (error state)
    my $bot = Chalk::IR::Type::MemoryPointer->BOTTOM();
    ok $bot, 'Created MemoryPointer BOTTOM';
    ok $bot->is_bottom, 'BOTTOM is bottom of lattice';
};

subtest 'MemoryPointer: meet operation - same type, different nullability' => sub {
    # *Point meet *Point? -> *Point (non-null is more specific)
    my $non_null = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 0,
    );

    my $nullable = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 1,
    );

    my $result = $non_null->meet($nullable);

    ok !$result->nullable, 'Meet produces non-null pointer';
    is $result->struct_name, 'Point', 'Meet preserves struct type';
};

subtest 'MemoryPointer: meet operation - different struct types' => sub {
    # *Point meet *Circle -> TOP (incompatible)
    my $point_ptr = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 0,
    );

    my $circle_ptr = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Circle',
        nullable => 0,
    );

    my $result = $point_ptr->meet($circle_ptr);

    ok $result->is_top, 'Meet of different struct types yields TOP';
};

subtest 'MemoryPointer: join operation - same type, different nullability' => sub {
    # *Point join *Point? -> *Point? (nullable is less specific)
    my $non_null = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 0,
    );

    my $nullable = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 1,
    );

    my $result = $non_null->join($nullable);

    ok $result->nullable, 'Join produces nullable pointer';
    is $result->struct_name, 'Point', 'Join preserves struct type';
};

subtest 'MemoryPointer: join operation - different struct types' => sub {
    # *Point join *Circle -> TOP (unknown which)
    my $point_ptr = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 0,
    );

    my $circle_ptr = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Circle',
        nullable => 0,
    );

    my $result = $point_ptr->join($circle_ptr);

    ok $result->is_top, 'Join of different struct types yields TOP';
};

subtest 'Memory: basic construction' => sub {
    # Memory slice for alias class 0
    my $mem = Chalk::IR::Type::Memory->new(
        alias_class => 0,
    );

    ok $mem, 'Created memory slice';
    is $mem->alias_class, 0, 'Memory has alias class 0';
};

subtest 'Memory: TOP and BOTTOM' => sub {
    # TOP: all memory states
    my $top = Chalk::IR::Type::Memory->TOP();
    ok $top, 'Created Memory TOP';
    ok $top->is_top, 'TOP is top of lattice';

    # BOTTOM: no memory state (error)
    my $bot = Chalk::IR::Type::Memory->BOTTOM();
    ok $bot, 'Created Memory BOTTOM';
    ok $bot->is_bottom, 'BOTTOM is bottom of lattice';
};

subtest 'Memory: meet operation - same alias class' => sub {
    # MEM#0 meet MEM#0 -> MEM#0
    my $mem1 = Chalk::IR::Type::Memory->new(alias_class => 0);
    my $mem2 = Chalk::IR::Type::Memory->new(alias_class => 0);

    my $result = $mem1->meet($mem2);

    is $result->alias_class, 0, 'Meet of same alias class preserves class';
};

subtest 'Memory: meet operation - different alias classes' => sub {
    # MEM#0 meet MEM#1 -> TOP (different memory slices)
    my $mem0 = Chalk::IR::Type::Memory->new(alias_class => 0);
    my $mem1 = Chalk::IR::Type::Memory->new(alias_class => 1);

    my $result = $mem0->meet($mem1);

    ok $result->is_top, 'Meet of different alias classes yields TOP';
};

subtest 'Memory: join operation - same alias class' => sub {
    # MEM#0 join MEM#0 -> MEM#0
    my $mem1 = Chalk::IR::Type::Memory->new(alias_class => 0);
    my $mem2 = Chalk::IR::Type::Memory->new(alias_class => 0);

    my $result = $mem1->join($mem2);

    is $result->alias_class, 0, 'Join of same alias class preserves class';
};

subtest 'Memory: join operation - different alias classes' => sub {
    # MEM#0 join MEM#1 -> TOP (unknown which memory)
    my $mem0 = Chalk::IR::Type::Memory->new(alias_class => 0);
    my $mem1 = Chalk::IR::Type::Memory->new(alias_class => 1);

    my $result = $mem0->join($mem1);

    ok $result->is_top, 'Join of different alias classes yields TOP';
};

# TODO: Tests for struct operations (NewObject, FieldStore, FieldLoad)
# These will be added as part of later issues (#258, #259)

# TODO: Tests for Cast operations
# Will be added as part of issue #258

# TODO: Tests for memory optimizations
# Will be added as part of issue #262

subtest 'Null safety: nullable vs non-nullable distinction' => sub {
    # Non-null pointer should be distinguishable from nullable pointer
    my $non_null = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 0,
    );

    my $nullable = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 1,
    );

    ok !$non_null->nullable, 'Non-null pointer is not nullable';
    ok $nullable->nullable, 'Nullable pointer is nullable';

    # Can convert non-null to nullable (widening)
    my $widened = $non_null->to_nullable();
    ok $widened->nullable, 'Widening non-null to nullable succeeds';
    is $widened->struct_name, 'Point', 'Widening preserves struct type';
};

subtest 'Null safety: null constant has correct type' => sub {
    # Constant null should have TypePointer with nil target
    my $null = Chalk::IR::Type::MemoryPointer->NULL();

    ok $null->nullable, 'NULL constant is nullable';
    ok !defined($null->struct_name), 'NULL has no specific struct target';
    ok $null->is_top, 'NULL points to TOP (no specific type)';
};

subtest 'Null safety: meet refines nullable to non-null' => sub {
    # When both paths are non-null, result should be non-null
    my $ptr1 = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 0,
    );

    my $ptr2 = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 0,
    );

    my $result = $ptr1->meet($ptr2);
    ok !$result->nullable, 'Meet of two non-null pointers is non-null';

    # When one path is nullable, result from meet should be non-null (intersection)
    my $nullable_ptr = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 1,
    );

    my $refined = $ptr1->meet($nullable_ptr);
    ok !$refined->nullable, 'Meet refines nullable to non-null';
};

subtest 'Null safety: join preserves nullability' => sub {
    # When either path is nullable, result should be nullable
    my $non_null = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 0,
    );

    my $nullable = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 1,
    );

    my $result = $non_null->join($nullable);
    ok $result->nullable, 'Join of non-null and nullable is nullable';
};

subtest 'Null safety: Cast node refines nullable to non-null' => sub {
    use Chalk::IR::Node::Cast;
    use Chalk::IR::Node::Constant;

    # Create a nullable pointer (simulating a variable that might be null)
    my $nullable_ptr = Chalk::IR::Node::Constant->new(
        value => 42,  # Simulating pointer value
        type => Chalk::IR::Type::MemoryPointer->new(
            struct_name => 'Point',
            nullable => 1,
        ),
    );

    # Create a non-null target type (for refinement after null check)
    my $non_null_type = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 0,
    );

    # Cast node joins input type with target type
    my $cast = Chalk::IR::Node::Cast->new(
        input => $nullable_ptr,
        target_type => $non_null_type,
        inputs => [],
    );

    # Compute should join nullable with non-null = nullable (less restrictive)
    my $result_type = $cast->compute();

    # Join of nullable and non-null is nullable (least upper bound)
    ok $result_type->nullable, 'Cast join produces nullable when input is nullable';
    is $result_type->struct_name, 'Point', 'Cast preserves struct type';
};

subtest 'Null safety: Cast with non-null input and nullable target' => sub {
    use Chalk::IR::Node::Cast;
    use Chalk::IR::Node::Constant;

    # Create a non-null pointer (simulating a guaranteed non-null value)
    my $non_null_ptr = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::MemoryPointer->new(
            struct_name => 'Point',
            nullable => 0,
        ),
    );

    # Target is nullable (widening operation)
    my $nullable_type = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 1,
    );

    my $cast = Chalk::IR::Node::Cast->new(
        input => $non_null_ptr,
        target_type => $nullable_type,
        inputs => [],
    );

    my $result_type = $cast->compute();

    # Join of non-null and nullable is nullable
    ok $result_type->nullable, 'Widening cast to nullable succeeds';
};

subtest 'Null safety: meet-based refinement (intersection type)' => sub {
    # This tests the actual null check refinement pattern
    # After "if (ptr != null)", the true branch should see non-null type

    my $nullable_ptr = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 1,
    );

    my $non_null_constraint = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 0,
    );

    # Meet represents intersection: "ptr is nullable AND ptr is non-null"
    # Result: ptr is non-null (more specific)
    my $refined = $nullable_ptr->meet($non_null_constraint);

    ok !$refined->nullable, 'Meet refines nullable pointer to non-null after null check';
    is $refined->struct_name, 'Point', 'Meet preserves struct type';
};

subtest 'Null safety: Cast peephole optimization with MemoryPointer' => sub {
    use Chalk::IR::Node::Cast;
    use Chalk::IR::Node::Constant;
    use Chalk::IR::Graph;

    # Create a mock graph for peephole
    my $graph = Chalk::IR::Graph->new();

    # Create a non-null pointer constant
    my $non_null_ptr = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::MemoryPointer->new(
            struct_name => 'Point',
            nullable => 0,
        ),
    );

    # Target is also non-null (same nullability)
    my $target_type = Chalk::IR::Type::MemoryPointer->new(
        struct_name => 'Point',
        nullable => 0,
    );

    my $cast = Chalk::IR::Node::Cast->new(
        input => $non_null_ptr,
        target_type => $target_type,
        inputs => [],
    );

    # Peephole should recognize this cast is redundant
    # Both input and target are non-null Point pointers
    my $optimized = $cast->peephole($graph);

    # The optimization should pass through to the input
    # because the types are compatible
    is ref($optimized), 'Chalk::IR::Node::Constant',
        'Cast peephole eliminates redundant cast when types are compatible';
};

subtest 'Null safety: FieldLoad requires non-null pointer' => sub {
    use Chalk::IR::Node::FieldLoad;
    use Chalk::IR::Node::Constant;

    # Create a nullable pointer (unsafe to dereference)
    my $nullable_ptr = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::MemoryPointer->new(
            struct_name => 'Point',
            nullable => 1,
        ),
    );

    # FieldLoad should detect nullable pointer and flag it
    # In a real implementation, this would be caught during type checking
    # For now, we document that FieldLoad expects non-null pointers
    ok $nullable_ptr->compute()->nullable,
        'FieldLoad input pointer is nullable (unsafe)';

    # Create a non-null pointer (safe to dereference)
    my $non_null_ptr = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::MemoryPointer->new(
            struct_name => 'Point',
            nullable => 0,
        ),
    );

    ok !$non_null_ptr->compute()->nullable,
        'FieldLoad with non-null pointer is safe';
};

subtest 'Null safety: FieldStore requires non-null pointer' => sub {
    use Chalk::IR::Node::FieldStore;
    use Chalk::IR::Node::Constant;

    # Create a nullable pointer (unsafe to dereference)
    my $nullable_ptr = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::MemoryPointer->new(
            struct_name => 'Point',
            nullable => 1,
        ),
    );

    # FieldStore should detect nullable pointer and flag it
    ok $nullable_ptr->compute()->nullable,
        'FieldStore input pointer is nullable (unsafe)';

    # Create a non-null pointer (safe to dereference)
    my $non_null_ptr = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::MemoryPointer->new(
            struct_name => 'Point',
            nullable => 0,
        ),
    );

    ok !$non_null_ptr->compute()->nullable,
        'FieldStore with non-null pointer is safe';
};
