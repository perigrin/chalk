# ABOUTME: Tests for Target/Perl lowering of StructRef and FieldAccess nodes.
# ABOUTME: Verifies StructRef→hash constructor and FieldAccess→hash key access.
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::Perl;
use Chalk::IR::NodeFactory;

# Helper: create a Constant node
sub const_node($type, $value) {
    my $factory = Chalk::IR::NodeFactory->new;
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

# === Test: StructRef lowering → hash constructor ===
{

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new();

    my $schema_node = const_node('string', 'earley_item_t');
    my $rule_val    = const_node('variable', '$rule');
    my $alt_val     = const_node('variable', '$alt_idx');

    my $struct = ctor('StructRef',
        schema => $schema_node,
        fields => [$rule_val, $alt_val],
    );

    # StructRef needs field names from the schema to emit as hash keys.
    # Pass schema metadata to the target for lowering.
    $target->set_struct_schemas({
        'earley_item_t' => {
            fields => [
                { name => 'rule',    c_type => 'SV *' },
                { name => 'alt_idx', c_type => 'IV'   },
            ],
        },
    });

    my $result = $target->emit_expr($struct);
    like($result, qr/\{/, 'StructRef lowered contains opening brace');
    like($result, qr/'rule'/, 'StructRef lowered contains rule key');
    like($result, qr/\$rule/, 'StructRef lowered contains $rule value');
    like($result, qr/'alt_idx'/, 'StructRef lowered contains alt_idx key');
    like($result, qr/\$alt_idx/, 'StructRef lowered contains $alt_idx value');
}

# === Test: FieldAccess lowering → hash key access ===
{

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new();

    my $schema_node  = const_node('string', 'earley_item_t');
    my $field_name   = const_node('string', 'core_id');
    my $target_var   = const_node('variable', '$item');

    my $access = ctor('FieldAccess',
        schema     => $schema_node,
        field_name => $field_name,
        target     => $target_var,
    );

    my $result = $target->emit_expr($access);
    is($result, q{$item->{'core_id'}}, 'FieldAccess lowered to hash key access');
}

done_testing;
