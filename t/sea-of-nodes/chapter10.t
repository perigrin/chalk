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

# TODO: Tests for null safety type refinement
# Will be added as part of issue #261
