# ABOUTME: Tests for the struct promotion schema analyzer (Pass 1).
# ABOUTME: Verifies detection of hash schemas, key accumulation, escape analysis, and C type inference.
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Optimizer::StructPromotion;

# Helper: create a Constant node
sub const_node($type, $value) {
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;
    return $factory->make('Constant', const_type => $type, value => $value);
}

# Helper: create a Constructor node
sub ctor($class, %inputs) {
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;
    return $factory->make('Constructor', class => $class, %inputs);
}

# === Test: Constructor detection — empty hash + literal-key assignments ===
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    # Build IR mimicking:
    #   my $item = {};
    #   $item->{rule} = $rule;
    #   $item->{alt_idx} = $alt_idx;
    #   $item->{core_id} = $core_id;
    #   $item->{dot} = $dot;
    #   $item->{origin} = $origin;
    #   $item->{value} = $value;
    #   return $item;

    my $item_var  = const_node('variable', '$item');
    my $rule_var  = const_node('variable', '$rule');
    my $alt_var   = const_node('variable', '$alt_idx');
    my $core_var  = const_node('variable', '$core_id');
    my $dot_var   = const_node('variable', '$dot');
    my $origin_var = const_node('variable', '$origin');
    my $value_var = const_node('variable', '$value');

    my $empty_hash = ctor('HashRefExpr', pairs => []);

    my $var_decl = ctor('VarDecl',
        variable    => $item_var,
        initializer => $empty_hash,
    );

    # Build assignment statements: $item->{key} = $val
    my @assigns;
    my @keys = qw(rule alt_idx core_id dot origin value);
    my @vals = ($rule_var, $alt_var, $core_var, $dot_var, $origin_var, $value_var);
    for my $i (0 .. $#keys) {
        my $subscript = ctor('SubscriptExpr',
            target => $item_var,
            index  => const_node('string', $keys[$i]),
            style  => const_node('enum', 'hash'),
        );
        my $assign = ctor('BinaryExpr',
            op    => const_node('string', '='),
            left  => $subscript,
            right => $vals[$i],
        );
        push @assigns, $assign;
    }

    my $return_stmt = ctor('ReturnStmt', value => $item_var);

    # Build method body
    my $method_body = [$var_decl, @assigns, $return_stmt];

    my $method = ctor('MethodDecl',
        name        => const_node('string', '_make_item'),
        params      => [$rule_var, $alt_var, const_node('variable', '$dot'),
                        const_node('variable', '$origin'), $value_var],
        body        => $method_body,
        return_type => undef,
    );

    my $class_body = [$method];
    my $class_decl = ctor('ClassDecl',
        name   => const_node('string', 'TestEarley'),
        parent => undef,
        body   => $class_body,
    );

    my $program = ctor('Program', statements => [$class_decl]);

    # Run analyzer
    my $analyzer = Chalk::Bootstrap::Optimizer::StructPromotion->new();
    my $schemas = $analyzer->analyze([
        {
            class_name => 'TestEarley',
            ir         => $program,
        }
    ]);

    ok(defined $schemas, 'analyze returns schemas');
    ok(ref $schemas eq 'HASH', 'schemas is a hashref');

    # Should detect one schema from the _make_item pattern
    my @schema_names = sort keys $schemas->%*;
    is(scalar @schema_names, 1, 'detected exactly one schema');

    my $schema = $schemas->{$schema_names[0]};
    ok(defined $schema, 'schema exists');

    # Check field names
    my @field_names = sort map { $_->{name} } $schema->{fields}->@*;
    is(\@field_names, [qw(alt_idx core_id dot origin rule value)],
        'schema has all 6 expected fields');
}

# === Test: Non-promotable hash — dynamic key ===
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $hash_var = const_node('variable', '$tags');
    my $empty_hash = ctor('HashRefExpr', pairs => []);
    my $var_decl = ctor('VarDecl',
        variable    => $hash_var,
        initializer => $empty_hash,
    );

    # Dynamic key: $tags->{$key} = 1
    my $dynamic_key = const_node('variable', '$key');
    my $subscript = ctor('SubscriptExpr',
        target => $hash_var,
        index  => $dynamic_key,
        style  => const_node('enum', 'hash'),
    );
    my $assign = ctor('BinaryExpr',
        op    => const_node('string', '='),
        left  => $subscript,
        right => const_node('integer', '1'),
    );

    my $method_body = [$var_decl, $assign];
    my $method = ctor('MethodDecl',
        name        => const_node('string', '_tag_it'),
        params      => [],
        body        => $method_body,
        return_type => undef,
    );

    my $class_decl = ctor('ClassDecl',
        name   => const_node('string', 'TestTags'),
        parent => undef,
        body   => [$method],
    );

    my $program = ctor('Program', statements => [$class_decl]);

    my $analyzer = Chalk::Bootstrap::Optimizer::StructPromotion->new();
    my $schemas = $analyzer->analyze([
        {
            class_name => 'TestTags',
            ir         => $program,
        }
    ]);

    # Dynamic key should prevent promotion
    is(scalar keys $schemas->%*, 0,
        'hash with dynamic key is not promoted');
}

# === Test: Schema unification — identical key sets get same schema ===
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    # Two methods both create hashes with same keys {a, b}
    my @methods;
    for my $mname (qw(make_foo make_bar)) {
        my $var = const_node('variable', '$h');
        my $empty = ctor('HashRefExpr', pairs => []);
        my $decl = ctor('VarDecl',
            variable    => $var,
            initializer => $empty,
        );

        my @stmts = ($decl);
        for my $key (qw(a b)) {
            my $sub = ctor('SubscriptExpr',
                target => $var,
                index  => const_node('string', $key),
                style  => const_node('enum', 'hash'),
            );
            push @stmts, ctor('BinaryExpr',
                op    => const_node('string', '='),
                left  => $sub,
                right => const_node('integer', '1'),
            );
        }

        push @methods, ctor('MethodDecl',
            name        => const_node('string', $mname),
            params      => [],
            body        => \@stmts,
            return_type => undef,
        );
    }

    my $class_decl = ctor('ClassDecl',
        name   => const_node('string', 'TestUnify'),
        parent => undef,
        body   => \@methods,
    );

    my $program = ctor('Program', statements => [$class_decl]);

    my $analyzer = Chalk::Bootstrap::Optimizer::StructPromotion->new();
    my $schemas = $analyzer->analyze([
        {
            class_name => 'TestUnify',
            ir         => $program,
        }
    ]);

    # Both should unify to one schema
    is(scalar keys $schemas->%*, 1,
        'identical key sets unified to one schema');
}

done_testing;
