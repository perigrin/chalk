#!/usr/bin/env perl
# ABOUTME: Tests Memory type alias class integration with Chalk's context model
# ABOUTME: Verifies alias_class enables optimization by proving non-aliasing
use 5.42.0;
use lib 'lib';
use Test::More tests => 13;
use Chalk::IR::Type::Memory;

# Test 1: Memory type with alias class
{
    my $mem1 = Chalk::IR::Type::Memory->new(alias_class => 1);
    is($mem1->alias_class, 1, 'Memory created with alias_class 1');
}

# Test 2: Different alias classes don't alias
{
    my $mem1 = Chalk::IR::Type::Memory->new(alias_class => 1);
    my $mem2 = Chalk::IR::Type::Memory->new(alias_class => 2);

    my $result = $mem1->meet($mem2);

    ok($result->is_top, 'Different alias classes meet to MemTop (no aliasing)');
}

# Test 3: Same alias class can alias
{
    my $mem1 = Chalk::IR::Type::Memory->new(alias_class => 1);
    my $mem2 = Chalk::IR::Type::Memory->new(alias_class => 1);

    my $result = $mem1->meet($mem2);

    is($result->alias_class, 1, 'Same alias classes meet to that class');
}

# Test 4: Memory TOP has no specific alias class
{
    my $mem_top = Chalk::IR::Type::Memory->TOP();

    ok($mem_top->is_top, 'Memory TOP is top');
    ok(!defined($mem_top->alias_class), 'Memory TOP has no alias_class');
}

# Test 5: Memory BOTTOM absorbs everything
{
    my $mem1 = Chalk::IR::Type::Memory->new(alias_class => 1);
    my $mem_bot = Chalk::IR::Type::Memory->BOTTOM();

    my $result = $mem1->meet($mem_bot);

    ok($result->is_bottom, 'Memory meet MemBot = MemBot');
}

# Test 6: Join of different alias classes = TOP
{
    my $mem1 = Chalk::IR::Type::Memory->new(alias_class => 1);
    my $mem2 = Chalk::IR::Type::Memory->new(alias_class => 2);

    my $result = $mem1->join($mem2);

    ok($result->is_top, 'Different alias classes join to MemTop');
}

# Test 7: Join of same alias class preserves it
{
    my $mem1 = Chalk::IR::Type::Memory->new(alias_class => 1);
    my $mem2 = Chalk::IR::Type::Memory->new(alias_class => 1);

    my $result = $mem1->join($mem2);

    is($result->alias_class, 1, 'Same alias classes join to that class');
}

# Test 8: MemTop meet specific class = specific class
{
    my $mem_top = Chalk::IR::Type::Memory->TOP();
    my $mem1 = Chalk::IR::Type::Memory->new(alias_class => 1);

    my $result = $mem_top->meet($mem1);

    is($result->alias_class, 1, 'MemTop meet specific = specific');
}

# Test 9: MemBot join specific class = specific class
{
    my $mem_bot = Chalk::IR::Type::Memory->BOTTOM();
    my $mem1 = Chalk::IR::Type::Memory->new(alias_class => 1);

    my $result = $mem_bot->join($mem1);

    is($result->alias_class, 1, 'MemBot join specific = specific');
}

# Test 10: Alias class assignment via field type
# In Chalk's model, each field type gets an alias class
# For example: "Point.x" (Int field) = alias_class 1
#              "Point.y" (Int field) = alias_class 2
#              "Circle.radius" (Int field) = alias_class 3
{
    # Simulate alias class assignment
    my %field_to_alias = (
        'Point.x' => 1,
        'Point.y' => 2,
        'Circle.radius' => 3,
    );

    my $point_x_mem = Chalk::IR::Type::Memory->new(alias_class => $field_to_alias{'Point.x'});
    my $point_y_mem = Chalk::IR::Type::Memory->new(alias_class => $field_to_alias{'Point.y'});

    # Different fields don't alias
    my $result = $point_x_mem->meet($point_y_mem);
    ok($result->is_top, 'Different struct fields have different alias classes');
}

# Test 11: Same field across instances uses same alias class
{
    # Both Point instances share alias_class for 'x' field
    my %field_to_alias = (
        'Point.x' => 1,
        'Point.y' => 2,
    );

    my $point1_x_mem = Chalk::IR::Type::Memory->new(alias_class => $field_to_alias{'Point.x'});
    my $point2_x_mem = Chalk::IR::Type::Memory->new(alias_class => $field_to_alias{'Point.x'});

    # Same field across instances CAN alias
    my $result = $point1_x_mem->meet($point2_x_mem);
    is($result->alias_class, 1, 'Same field across instances can alias');
}

# Test 12: Undefined alias_class treated as TOP
{
    my $mem_undef = Chalk::IR::Type::Memory->new();
    my $mem1 = Chalk::IR::Type::Memory->new(alias_class => 1);

    my $result = $mem_undef->meet($mem1);

    is($result->alias_class, 1, 'Undefined alias_class (TOP) meet specific = specific');
}
