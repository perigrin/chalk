# ABOUTME: Tests for TernaryExpr, StructRef, and StructFieldAccess typed IR nodes.
# ABOUTME: Verifies operation(), isa hierarchy, shim translation, and compat_class.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Shim;

my $f = Chalk::IR::NodeFactory->new();

Chalk::IR::Shim::reset_enabled();

sub const_node($val, $type = 'string') {
    return $f->make('Constant', value => $val, const_type => $type, inputs => []);
}

sub with_enabled($class, $code) {
    Chalk::IR::Shim::enable_class($class);
    $code->();
    Chalk::IR::Shim::reset_enabled();
}

# ---- TernaryExpr typed node ----

subtest 'TernaryExpr node: operation and isa hierarchy' => sub {
    use Chalk::IR::Node::TernaryExpr;
    use Chalk::IR::Node;

    my $cond       = const_node('$x');
    my $true_expr  = const_node('1', 'integer');
    my $false_expr = const_node('0', 'integer');

    my $node = Chalk::IR::Node::TernaryExpr->new(
        id     => 'ternary_0',
        inputs => [$cond, $true_expr, $false_expr],
    );

    is($node->operation(), 'TernaryExpr', 'TernaryExpr operation()');
    is($node->class(), 'TernaryExpr', 'TernaryExpr class() returns operation when no compat_class');
    isa_ok($node, 'Chalk::IR::Node', 'TernaryExpr isa Chalk::IR::Node');
    isa_ok($node, 'Chalk::Bootstrap::IR::Node', 'TernaryExpr isa Chalk::Bootstrap::IR::Node');
    is(scalar($node->inputs()->@*), 3, 'TernaryExpr has 3 inputs');
};

subtest 'TernaryExpr shim translation' => sub {
    with_enabled('TernaryExpr', sub {
        my $cond       = const_node('$x');
        my $true_expr  = const_node('1', 'integer');
        my $false_expr = const_node('0', 'integer');

        my $node = Chalk::IR::Shim::translate($f, 'TernaryExpr',
            condition  => $cond,
            true_expr  => $true_expr,
            false_expr => $false_expr,
        );

        ok(defined $node, 'TernaryExpr translation returns a node');
        isa_ok($node, 'Chalk::IR::Node::TernaryExpr', 'TernaryExpr shim isa TernaryExpr');
        is($node->class(), 'TernaryExpr', 'TernaryExpr class() returns compat_class');
        is(scalar($node->inputs()->@*), 3, 'TernaryExpr shim node has 3 inputs');
        is($node->inputs()->[0]->id(), $cond->id(), 'first input is condition');
        is($node->inputs()->[1]->id(), $true_expr->id(), 'second input is true_expr');
        is($node->inputs()->[2]->id(), $false_expr->id(), 'third input is false_expr');
    });
};

subtest 'TernaryExpr is enabled by default' => sub {
    my $node = Chalk::IR::Shim::translate($f, 'TernaryExpr',
        condition  => const_node('$x'),
        true_expr  => const_node('1', 'integer'),
        false_expr => const_node('0', 'integer'),
    );
    ok(defined $node, 'TernaryExpr is translated by default (in DEFAULT_ENABLED)');
    isa_ok($node, 'Chalk::IR::Node::TernaryExpr', 'default-enabled TernaryExpr isa TernaryExpr');
};

# ---- StructRef typed node ----

subtest 'StructRef node: operation and isa hierarchy' => sub {
    use Chalk::IR::Node::StructRef;
    use Chalk::IR::Node;

    my $schema = const_node('MySchema');
    my $fields = const_node('[]');

    my $node = Chalk::IR::Node::StructRef->new(
        id     => 'structref_0',
        inputs => [$schema, $fields],
    );

    is($node->operation(), 'StructRef', 'StructRef operation()');
    is($node->class(), 'StructRef', 'StructRef class() returns operation');
    isa_ok($node, 'Chalk::IR::Node', 'StructRef isa Chalk::IR::Node');
    is(scalar($node->inputs()->@*), 2, 'StructRef has 2 inputs');
};

subtest 'StructRef shim translation' => sub {
    with_enabled('StructRef', sub {
        my $schema = const_node('MySchema');
        my $fields = const_node('[]');

        my $node = Chalk::IR::Shim::translate($f, 'StructRef',
            schema => $schema,
            fields => $fields,
        );

        ok(defined $node, 'StructRef translation returns a node');
        isa_ok($node, 'Chalk::IR::Node::StructRef', 'StructRef shim isa StructRef');
        is($node->class(), 'StructRef', 'StructRef class() returns compat_class');
        is($node->inputs()->[0]->id(), $schema->id(), 'first input is schema');
        is($node->inputs()->[1]->id(), $fields->id(), 'second input is fields');
    });
};

subtest 'StructRef is enabled by default' => sub {
    my $node = Chalk::IR::Shim::translate($f, 'StructRef',
        schema => const_node('MySchema'),
        fields => const_node('[]'),
    );
    ok(defined $node, 'StructRef is translated by default (in DEFAULT_ENABLED)');
    isa_ok($node, 'Chalk::IR::Node::StructRef', 'default-enabled StructRef isa StructRef');
};

# ---- StructFieldAccess typed node ----

subtest 'StructFieldAccess node: operation and isa hierarchy' => sub {
    use Chalk::IR::Node::StructFieldAccess;
    use Chalk::IR::Node;

    my $schema     = const_node('MySchema');
    my $field_name = const_node('my_field');
    my $target     = const_node('$obj');

    my $node = Chalk::IR::Node::StructFieldAccess->new(
        id     => 'sfa_0',
        inputs => [$schema, $field_name, $target],
    );

    is($node->operation(), 'StructFieldAccess', 'StructFieldAccess operation()');
    is($node->class(), 'StructFieldAccess', 'StructFieldAccess class() returns operation');
    isa_ok($node, 'Chalk::IR::Node', 'StructFieldAccess isa Chalk::IR::Node');
    is(scalar($node->inputs()->@*), 3, 'StructFieldAccess has 3 inputs');
};

subtest 'FieldAccess constructor class maps to StructFieldAccess typed node' => sub {
    with_enabled('FieldAccess', sub {
        my $schema     = const_node('MySchema');
        my $field_name = const_node('my_field');
        my $target     = const_node('$obj');

        my $node = Chalk::IR::Shim::translate($f, 'FieldAccess',
            schema     => $schema,
            field_name => $field_name,
            target     => $target,
        );

        ok(defined $node, 'FieldAccess translation returns a node');
        isa_ok($node, 'Chalk::IR::Node::StructFieldAccess', 'FieldAccess shim isa StructFieldAccess');
        is($node->class(), 'FieldAccess', 'FieldAccess class() returns FieldAccess compat_class');
        is($node->inputs()->[0]->id(), $schema->id(), 'first input is schema');
        is($node->inputs()->[1]->id(), $field_name->id(), 'second input is field_name');
        is($node->inputs()->[2]->id(), $target->id(), 'third input is target');
    });
};

subtest 'FieldAccess is enabled by default' => sub {
    my $node = Chalk::IR::Shim::translate($f, 'FieldAccess',
        schema     => const_node('MySchema'),
        field_name => const_node('my_field'),
        target     => const_node('$obj'),
    );
    ok(defined $node, 'FieldAccess is translated by default (in DEFAULT_ENABLED)');
    isa_ok($node, 'Chalk::IR::Node::StructFieldAccess', 'default-enabled FieldAccess isa StructFieldAccess');
};

done_testing();
