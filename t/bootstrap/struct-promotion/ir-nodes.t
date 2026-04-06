# ABOUTME: Tests for StructRef and FieldAccess IR node types used by struct promotion.
# ABOUTME: Verifies creation via NodeFactory, correct class values, and hash consing.
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory to ensure clean test state
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

# === StructRef node type ===

# Test: Create StructRef via NodeFactory with schema name + field values
{
    my $schema_node = $factory->make('Constant',
        const_type => 'string',
        value      => 'earley_item_t',
    );

    my $rule_val = $factory->make('Constant',
        const_type => 'string',
        value      => 'some_rule',
    );

    my $alt_val = $factory->make('Constant',
        const_type => 'integer',
        value      => '0',
    );

    my $struct = $factory->make('Constructor',
        class  => 'StructRef',
        schema => $schema_node,
        fields => [$rule_val, $alt_val],
    );

    ok(defined $struct, 'StructRef node created');
    is($struct->operation, 'StructRef', 'operation is StructRef');
    is($struct->class, 'StructRef', 'class is StructRef');
}

# === FieldAccess node type ===

# Test: Create FieldAccess via NodeFactory with schema + field name + target
{
    my $schema_node = $factory->make('Constant',
        const_type => 'string',
        value      => 'earley_item_t',
    );

    my $field_name_node = $factory->make('Constant',
        const_type => 'string',
        value      => 'core_id',
    );

    my $target_node = $factory->make('Constant',
        const_type => 'string',
        value      => 'item_sv',
    );

    my $access = $factory->make('Constructor',
        class      => 'FieldAccess',
        schema     => $schema_node,
        field_name => $field_name_node,
        target     => $target_node,
    );

    ok(defined $access, 'FieldAccess node created');
    is($access->operation, 'StructFieldAccess', 'operation is StructFieldAccess');
    is($access->class, 'FieldAccess', 'class is FieldAccess');
}

# === Hash consing verification ===

# Test: Two identical StructRef nodes share same ID (hash consing)
{
    my $schema1 = $factory->make('Constant',
        const_type => 'string',
        value      => 'test_schema_t',
    );

    my $field1 = $factory->make('Constant',
        const_type => 'integer',
        value      => '42',
    );

    my $struct_a = $factory->make('Constructor',
        class  => 'StructRef',
        schema => $schema1,
        fields => [$field1],
    );

    my $struct_b = $factory->make('Constructor',
        class  => 'StructRef',
        schema => $schema1,
        fields => [$field1],
    );

    is(refaddr($struct_a), refaddr($struct_b),
        'identical StructRef nodes share same reference (hash consed)');
}

# Test: Two identical FieldAccess nodes share same ID
{
    my $schema = $factory->make('Constant',
        const_type => 'string',
        value      => 'test_schema_t',
    );

    my $fname = $factory->make('Constant',
        const_type => 'string',
        value      => 'x',
    );

    my $target = $factory->make('Constant',
        const_type => 'string',
        value      => 'obj_sv',
    );

    my $access_a = $factory->make('Constructor',
        class      => 'FieldAccess',
        schema     => $schema,
        field_name => $fname,
        target     => $target,
    );

    my $access_b = $factory->make('Constructor',
        class      => 'FieldAccess',
        schema     => $schema,
        field_name => $fname,
        target     => $target,
    );

    is(refaddr($access_a), refaddr($access_b),
        'identical FieldAccess nodes share same reference (hash consed)');
}

# Test: Different StructRef nodes (different fields) are NOT deduplicated
{
    my $schema = $factory->make('Constant',
        const_type => 'string',
        value      => 'test_schema_t',
    );

    my $field_a = $factory->make('Constant',
        const_type => 'integer',
        value      => '1',
    );

    my $field_b = $factory->make('Constant',
        const_type => 'integer',
        value      => '2',
    );

    my $struct_x = $factory->make('Constructor',
        class  => 'StructRef',
        schema => $schema,
        fields => [$field_a],
    );

    my $struct_y = $factory->make('Constructor',
        class  => 'StructRef',
        schema => $schema,
        fields => [$field_b],
    );

    isnt(refaddr($struct_x), refaddr($struct_y),
        'different StructRef nodes are NOT hash-consed together');
}

done_testing;
