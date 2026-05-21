# ABOUTME: Tests for Target/C emission of StructRef and FieldAccess IR nodes.
# ABOUTME: Verifies typedef, struct allocation, direct field access, and copy-with-override.
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::EmitHelpers;
use Chalk::IR::NodeFactory;

# Helper: create a Constant node
sub const_node($type, $value) {
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;
    return $factory->make('Constant', const_type => $type, value => $value);
}

# Helper: create a typed IR node by legacy Constructor class name.
# Dispatches directly to Chalk::IR::NodeFactory and preserves compat_class
# so $node->class() still returns the legacy name expected by emitters.
sub ctor($class, %inputs) {
    state $typed = Chalk::IR::NodeFactory->new;
    if ($class eq 'StructRef') {
        return $typed->make('StructRef',
            inputs       => [$inputs{schema}, $inputs{fields}],
            compat_class => 'StructRef',
        );
    }
    if ($class eq 'FieldAccess') {
        return $typed->make('StructFieldAccess',
            inputs       => [$inputs{schema}, $inputs{field_name}, $inputs{target}],
            compat_class => 'FieldAccess',
        );
    }
    die "ctor: unsupported class '$class'";
}

# We need an EmitHelpers instance — it's abstract but we can use Target::C
# which inherits from it. For unit testing, let's just test via a minimal subclass.
# Target::C requires many setup calls, so let's use it directly with minimal config.
use Chalk::Bootstrap::Perl::Target::C;

# === Test: StructRef allocation emission ===
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $target = Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Test::StructRef',
    );

    my $schema_meta = {
        'earley_item_t' => {
            fields => [
                { name => 'rule',    c_type => 'SV *' },
                { name => 'alt_idx', c_type => 'IV'   },
            ],
        },
    };
    $target->set_struct_schemas($schema_meta);

    my $schema_node = const_node('string', 'earley_item_t');
    my $rule_val    = const_node('variable', '$rule');
    my $alt_val     = const_node('integer', '3');

    my $struct = ctor('StructRef',
        schema => $schema_node,
        fields => [$rule_val, $alt_val],
    );

    my $declared_vars = { 'rule' => 1 };
    my $result = $target->emit_struct_ref($struct, $declared_vars);

    ok(defined $result, 'emit_struct_ref returns C code');
    like($result, qr/newSV\(sizeof\(earley_item_t\)\)/,
        'emits newSV(sizeof(T)) allocation');
    like($result, qr/SvPOK_on/,
        'emits SvPOK_on to mark as string-like');
    like($result, qr/SvCUR_set/,
        'emits SvCUR_set for size');
    like($result, qr/earley_item_t\s*\*/,
        'casts to struct pointer');
    like($result, qr/->rule\s*=/,
        'assigns rule field');
    like($result, qr/->alt_idx\s*=/,
        'assigns alt_idx field');
}

# === Test: FieldAccess emission — IV field ===
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $target = Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Test::FieldAccess',
    );

    my $schema_meta = {
        'earley_item_t' => {
            fields => [
                { name => 'core_id', c_type => 'IV' },
                { name => 'rule',    c_type => 'SV *' },
            ],
        },
    };
    $target->set_struct_schemas($schema_meta);

    my $schema_node  = const_node('string', 'earley_item_t');
    my $field_name   = const_node('string', 'core_id');
    my $target_var   = const_node('variable', '$item');

    my $access = ctor('FieldAccess',
        schema     => $schema_node,
        field_name => $field_name,
        target     => $target_var,
    );

    my $declared_vars = { 'item' => 1 };
    my $result = $target->emit_field_access($access, $declared_vars);

    ok(defined $result, 'emit_field_access returns C code');
    like($result, qr/earley_item_t\s*\*\)/,
        'casts SvPVX to struct pointer');
    like($result, qr/SvPVX/,
        'uses SvPVX to get buffer');
    like($result, qr/->core_id/,
        'accesses core_id field');
    # IV field should be wrapped in newSViv when returning as SV*
    like($result, qr/newSViv/,
        'IV field wrapped in newSViv for SV* context');
}

# === Test: FieldAccess emission — SV* field (no wrapping) ===
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $target = Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Test::FieldAccessSV',
    );

    my $schema_meta = {
        'earley_item_t' => {
            fields => [
                { name => 'rule', c_type => 'SV *' },
            ],
        },
    };
    $target->set_struct_schemas($schema_meta);

    my $access = ctor('FieldAccess',
        schema     => const_node('string', 'earley_item_t'),
        field_name => const_node('string', 'rule'),
        target     => const_node('variable', '$item'),
    );

    my $declared_vars = { 'item' => 1 };
    my $result = $target->emit_field_access($access, $declared_vars);

    ok(defined $result, 'emit_field_access returns C code for SV* field');
    like($result, qr/->rule/,
        'accesses rule field');
    unlike($result, qr/newSViv/,
        'SV* field NOT wrapped in newSViv');
}

# === Test: typedef generation ===
{
    my $schema_meta = {
        'earley_item_t' => {
            fields => [
                { name => 'rule',    c_type => 'SV *' },
                { name => 'alt_idx', c_type => 'IV'   },
                { name => 'core_id', c_type => 'IV'   },
            ],
        },
    };

    my $target = Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Test::Typedef',
    );
    $target->set_struct_schemas($schema_meta);

    my $typedef = $target->generate_typedefs();
    ok(defined $typedef, 'generate_typedefs returns code');
    like($typedef, qr/typedef struct/,
        'contains typedef struct');
    like($typedef, qr/earley_item_t/,
        'contains schema name');
    like($typedef, qr/SV \*\s*rule/,
        'contains SV* field');
    like($typedef, qr/IV\s+alt_idx/,
        'contains IV field');
}

done_testing;
