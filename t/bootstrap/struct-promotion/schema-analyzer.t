# ABOUTME: Tests for the struct promotion schema analyzer (Pass 1).
# ABOUTME: Verifies detection of hash schemas, key accumulation, escape analysis, and C type inference.
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Optimizer::StructPromotion;
use Chalk::IR::Node::Return;
use Chalk::IR::MethodInfo;
use Chalk::IR::SubInfo;
use Chalk::IR::ClassInfo;
use Chalk::IR::Program;

# Helper: create a Constant node
sub const_node($type, $value) {
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;
    return $factory->make('Constant', const_type => $type, value => $value);
}

# Helper: create a computation IR node (VarDecl, BinaryExpr, etc.)
sub ctor($class, %inputs) {
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;
    return $factory->make('Constructor', class => $class, %inputs);
}

# Helper: create a Return CFG node
sub ret_node($val) {
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;
    return $factory->make_cfg('Return',
        inputs => [ $factory->make('Start'), $val ],
    );
}

# Helper: create a MethodInfo metadata struct
sub method_info($name, $body, %opts) {
    return Chalk::IR::MethodInfo->new(
        name        => $name,
        params      => $opts{params} // [],
        return_type => $opts{return_type},
        body        => $body,
    );
}

# Helper: create a ClassInfo metadata struct with a list of body items
sub class_info($name, @body) {
    my (@methods, @subs, @fields);
    for my $item (@body) {
        if ($item isa Chalk::IR::MethodInfo) { push @methods, $item; }
        elsif ($item isa Chalk::IR::SubInfo)  { push @subs,    $item; }
    }
    return Chalk::IR::ClassInfo->new(
        name    => $name,
        methods => \@methods,
        subs    => \@subs,
        fields  => \@fields,
        body    => \@body,
    );
}

# Helper: create a Program IR struct wrapping a single class
sub program_ir($class_info) {
    return Chalk::IR::Program->new(
        classes => [$class_info],
    );
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

    my $return_stmt = ret_node($item_var);

    # Build method body
    my $method_body = [$var_decl, @assigns, $return_stmt];

    my $method = method_info('_make_item', $method_body,
        params => [$rule_var, $alt_var, const_node('variable', '$dot'),
                   const_node('variable', '$origin'), $value_var],
    );

    my $class_decl = class_info('TestEarley', $method);
    my $program = program_ir($class_decl);

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
    my $method = method_info('_tag_it', $method_body);
    my $class_decl = class_info('TestTags', $method);
    my $program = program_ir($class_decl);

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

        push @methods, method_info($mname, \@stmts);
    }

    my $class_decl = class_info('TestUnify', @methods);
    my $program = program_ir($class_decl);

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

# === Test: Escape analysis — hash returned from public method is NOT promoted ===
# A public method (not starting with _) that returns a hash variable means
# uncompiled code could call it and see the hash.
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $var = const_node('variable', '$result');
    my $empty = ctor('HashRefExpr', pairs => []);
    my $decl = ctor('VarDecl',
        variable    => $var,
        initializer => $empty,
    );

    my $sub = ctor('SubscriptExpr',
        target => $var,
        index  => const_node('string', 'status'),
        style  => const_node('enum', 'hash'),
    );
    my $assign = ctor('BinaryExpr',
        op    => const_node('string', '='),
        left  => $sub,
        right => const_node('string', 'ok'),
    );

    my $return_stmt = ret_node($var);

    # Public method (no _ prefix)
    my $method = method_info('get_result', [$decl, $assign, $return_stmt]);
    my $class_decl = class_info('TestEscape', $method);
    my $program = program_ir($class_decl);

    my $analyzer = Chalk::Bootstrap::Optimizer::StructPromotion->new();
    my $schemas = $analyzer->analyze([
        {
            class_name => 'TestEscape',
            ir         => $program,
        }
    ]);

    is(scalar keys $schemas->%*, 0,
        'hash returned from public method is NOT promoted (escape analysis)');
}

# === Test: Escape analysis — hash returned from private method IS promoted ===
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $var = const_node('variable', '$item');
    my $empty = ctor('HashRefExpr', pairs => []);
    my $decl = ctor('VarDecl',
        variable    => $var,
        initializer => $empty,
    );

    my $sub = ctor('SubscriptExpr',
        target => $var,
        index  => const_node('string', 'x'),
        style  => const_node('enum', 'hash'),
    );
    my $assign = ctor('BinaryExpr',
        op    => const_node('string', '='),
        left  => $sub,
        right => const_node('integer', '1'),
    );

    my $return_stmt = ret_node($var);

    # Private method (_ prefix) — all callers are compiled
    my $method = method_info('_make_item', [$decl, $assign, $return_stmt]);
    my $class_decl = class_info('TestPrivate', $method);
    my $program = program_ir($class_decl);

    my $analyzer = Chalk::Bootstrap::Optimizer::StructPromotion->new();
    my $schemas = $analyzer->analyze([
        {
            class_name => 'TestPrivate',
            ir         => $program,
        }
    ]);

    is(scalar keys $schemas->%*, 1,
        'hash returned from private method IS promoted');
}

# === Test: C type inference — fields used in integer context get IV ===
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $item_var = const_node('variable', '$item');
    my $empty = ctor('HashRefExpr', pairs => []);
    my $decl = ctor('VarDecl',
        variable    => $item_var,
        initializer => $empty,
    );

    # $item->{count} = 0  (integer literal)
    my $count_sub = ctor('SubscriptExpr',
        target => $item_var,
        index  => const_node('string', 'count'),
        style  => const_node('enum', 'hash'),
    );
    my $assign_count = ctor('BinaryExpr',
        op    => const_node('string', '='),
        left  => $count_sub,
        right => const_node('integer', '0'),
    );

    # $item->{count} + 1 (arithmetic usage)
    my $count_read = ctor('SubscriptExpr',
        target => $item_var,
        index  => const_node('string', 'count'),
        style  => const_node('enum', 'hash'),
    );
    my $arith = ctor('BinaryExpr',
        op    => const_node('string', '+'),
        left  => $count_read,
        right => const_node('integer', '1'),
    );

    # $item->{name} = $name  (variable — SV* by default)
    my $name_sub = ctor('SubscriptExpr',
        target => $item_var,
        index  => const_node('string', 'name'),
        style  => const_node('enum', 'hash'),
    );
    my $assign_name = ctor('BinaryExpr',
        op    => const_node('string', '='),
        left  => $name_sub,
        right => const_node('variable', '$name'),
    );

    my $method = method_info('_process', [$decl, $assign_count, $arith, $assign_name]);
    my $class_decl = class_info('TestTypes', $method);
    my $program = program_ir($class_decl);

    my $analyzer = Chalk::Bootstrap::Optimizer::StructPromotion->new();
    my $schemas = $analyzer->analyze([
        {
            class_name => 'TestTypes',
            ir         => $program,
        }
    ]);

    my @schema_names = sort keys $schemas->%*;
    is(scalar @schema_names, 1, 'one schema detected');

    my $schema = $schemas->{$schema_names[0]};
    my %field_types = map { $_->{name} => $_->{c_type} } $schema->{fields}->@*;

    is($field_types{count}, 'IV', 'count field inferred as IV (integer usage)');
    is($field_types{name}, 'SV *', 'name field remains SV* (variable usage)');
}

# === Test: Escape analysis — hash passed to call_method on unknown class NOT promoted ===
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $var = const_node('variable', '$data');
    my $empty = ctor('HashRefExpr', pairs => []);
    my $decl = ctor('VarDecl',
        variable    => $var,
        initializer => $empty,
    );

    my $sub = ctor('SubscriptExpr',
        target => $var,
        index  => const_node('string', 'key'),
        style  => const_node('enum', 'hash'),
    );
    my $assign = ctor('BinaryExpr',
        op    => const_node('string', '='),
        left  => $sub,
        right => const_node('integer', '1'),
    );

    # Pass hash to a method call on an unknown object: $obj->process($data)
    my $method_call = ctor('MethodCallExpr',
        invocant    => const_node('variable', '$obj'),
        method_name => const_node('string', 'process'),
        args        => [$var],
    );

    my $method = method_info('_internal', [$decl, $assign, $method_call]);
    my $class_decl = class_info('TestCallEscape', $method);
    my $program = program_ir($class_decl);

    # Compile only TestCallEscape — $obj could be uncompiled
    my $analyzer = Chalk::Bootstrap::Optimizer::StructPromotion->new();
    my $schemas = $analyzer->analyze([
        {
            class_name => 'TestCallEscape',
            ir         => $program,
        }
    ]);

    is(scalar keys $schemas->%*, 0,
        'hash passed as arg to method call on unknown object is NOT promoted');
}

done_testing;
