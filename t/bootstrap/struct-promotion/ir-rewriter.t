# ABOUTME: Tests for the struct promotion IR rewriter (Pass 2).
# ABOUTME: Verifies HashRefExpr→StructRef and SubscriptExpr→FieldAccess rewrites.
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Optimizer::StructPromotion;
use Chalk::IR::Node::Return;

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

# Helper: create a Return CFG node
sub ret_node($val) {
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;
    return $factory->make_cfg('Return',
        inputs => [ $factory->make('Start'), $val ],
    );
}

# === Test: Constructor rewrite — empty hash + assignments → StructRef ===
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $item_var = const_node('variable', '$item');
    my $rule_var = const_node('variable', '$rule');
    my $dot_var  = const_node('variable', '$dot');

    my $empty_hash = ctor('HashRefExpr', pairs => []);
    my $var_decl = ctor('VarDecl',
        variable    => $item_var,
        initializer => $empty_hash,
    );

    # $item->{rule} = $rule
    my $sub_rule = ctor('SubscriptExpr',
        target => $item_var,
        index  => const_node('string', 'rule'),
        style  => const_node('enum', 'hash'),
    );
    my $assign_rule = ctor('BinaryExpr',
        op    => const_node('string', '='),
        left  => $sub_rule,
        right => $rule_var,
    );

    # $item->{dot} = $dot
    my $sub_dot = ctor('SubscriptExpr',
        target => $item_var,
        index  => const_node('string', 'dot'),
        style  => const_node('enum', 'hash'),
    );
    my $assign_dot = ctor('BinaryExpr',
        op    => const_node('string', '='),
        left  => $sub_dot,
        right => $dot_var,
    );

    my $return_stmt = ret_node($item_var);

    my $method = ctor('MethodDecl',
        name        => const_node('string', '_make_item'),
        params      => [$rule_var, $dot_var],
        body        => [$var_decl, $assign_rule, $assign_dot, $return_stmt],
        return_type => undef,
    );

    my $class_decl = ctor('ClassDecl',
        name   => const_node('string', 'TestRewrite'),
        parent => undef,
        body   => [$method],
    );

    my $program = ctor('Program', statements => [$class_decl]);

    # Run analyze + rewrite
    my $optimizer = Chalk::Bootstrap::Optimizer::StructPromotion->new();
    my $schemas = $optimizer->analyze([
        { class_name => 'TestRewrite', ir => $program }
    ]);

    is(scalar keys $schemas->%*, 1, 'one schema detected');

    my $rewritten = $optimizer->rewrite(
        [{ class_name => 'TestRewrite', ir => $program }],
        $schemas,
    );

    ok(defined $rewritten, 'rewrite returns result');

    # Walk the rewritten IR to find StructRef
    my $found_struct_ref = false;
    my $found_field_access = false;
    my @work = ($rewritten->[0]{ir});
    while (@work) {
        my $node = shift @work;
        next unless defined $node;
        if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
            if ($node->class() eq 'StructRef') {
                $found_struct_ref = true;
            }
            if ($node->class() eq 'FieldAccess') {
                $found_field_access = true;
            }
        }
        next unless $node isa Chalk::IR::Node;
        for my $input ($node->inputs()->@*) {
            next unless defined $input;
            if (ref($input) eq 'ARRAY') {
                push @work, grep { defined } $input->@*;
            } else {
                push @work, $input;
            }
        }
    }

    # After rewrite, the empty hash + assignments should be replaced by StructRef
    ok($found_struct_ref, 'rewritten IR contains StructRef node');
}

# === Test: Access site rewrite — SubscriptExpr → FieldAccess ===
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $item_var = const_node('variable', '$item');
    my $empty_hash = ctor('HashRefExpr', pairs => []);
    my $var_decl = ctor('VarDecl',
        variable    => $item_var,
        initializer => $empty_hash,
    );

    # $item->{x} = 1
    my $sub_x = ctor('SubscriptExpr',
        target => $item_var,
        index  => const_node('string', 'x'),
        style  => const_node('enum', 'hash'),
    );
    my $assign_x = ctor('BinaryExpr',
        op    => const_node('string', '='),
        left  => $sub_x,
        right => const_node('integer', '1'),
    );

    # Read: $item->{x} (in expression context, not assignment)
    my $read_x = ctor('SubscriptExpr',
        target => $item_var,
        index  => const_node('string', 'x'),
        style  => const_node('enum', 'hash'),
    );

    my $use_x = ctor('BuiltinCall',
        name => const_node('string', 'say'),
        args => [$read_x],
    );

    my $method = ctor('MethodDecl',
        name        => const_node('string', '_reader'),
        params      => [],
        body        => [$var_decl, $assign_x, $use_x],
        return_type => undef,
    );

    my $class_decl = ctor('ClassDecl',
        name   => const_node('string', 'TestAccess'),
        parent => undef,
        body   => [$method],
    );

    my $program = ctor('Program', statements => [$class_decl]);

    my $optimizer = Chalk::Bootstrap::Optimizer::StructPromotion->new();
    my $schemas = $optimizer->analyze([
        { class_name => 'TestAccess', ir => $program }
    ]);

    my $rewritten = $optimizer->rewrite(
        [{ class_name => 'TestAccess', ir => $program }],
        $schemas,
    );

    # Walk rewritten IR to find FieldAccess
    my $found_field_access = false;
    my @work = ($rewritten->[0]{ir});
    while (@work) {
        my $node = shift @work;
        next unless defined $node;
        if ($node isa Chalk::Bootstrap::IR::Node::Constructor
            && $node->class() eq 'FieldAccess') {
            $found_field_access = true;
        }
        next unless $node isa Chalk::IR::Node;
        for my $input ($node->inputs()->@*) {
            next unless defined $input;
            if (ref($input) eq 'ARRAY') {
                push @work, grep { defined } $input->@*;
            } else {
                push @work, $input;
            }
        }
    }

    ok($found_field_access, 'rewritten IR contains FieldAccess for read-site subscript');
}

done_testing;
