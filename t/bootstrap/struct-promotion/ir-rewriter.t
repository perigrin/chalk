# ABOUTME: Tests for the struct promotion IR rewriter (Pass 2).
# ABOUTME: Verifies HashRefExpr→StructRef and SubscriptExpr→FieldAccess rewrites.
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Optimizer::StructPromotion;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::StructFieldAccess;
use Chalk::IR::MethodInfo;
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

# Helper: walk an IR tree collecting all typed nodes
# Handles Chalk::IR::Program, Chalk::IR::ClassInfo, Chalk::IR::MethodInfo,
# and Chalk::IR::Node subclasses
sub walk_ir($root, $visitor) {
    my @work = ($root);
    while (@work) {
        my $node = shift @work;
        next unless defined $node;
        $visitor->($node);
        if ($node isa Chalk::IR::Program) {
            push @work, $node->classes()->@*;
        } elsif ($node isa Chalk::IR::ClassInfo) {
            push @work, $node->body()->@*;
        } elsif ($node isa Chalk::IR::MethodInfo) {
            push @work, $node->body()->@*;
        } elsif ($node isa Chalk::IR::Node) {
            for my $input ($node->inputs()->@*) {
                next unless defined $input;
                if (ref($input) eq 'ARRAY') {
                    push @work, grep { defined } $input->@*;
                } else {
                    push @work, $input;
                }
            }
        }
    }
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

    my $method = method_info('_make_item',
        [$var_decl, $assign_rule, $assign_dot, $return_stmt],
        params => [$rule_var, $dot_var],
    );

    my $class_decl = class_info('TestRewrite', $method);
    my $program = program_ir($class_decl);

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
    walk_ir($rewritten->[0]{ir}, sub($node) {
        if ($node isa Chalk::IR::Node && $node->class() eq 'StructRef') {
            $found_struct_ref = true;
        }
    });

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

    my $method = method_info('_reader', [$var_decl, $assign_x, $use_x]);
    my $class_decl = class_info('TestAccess', $method);
    my $program = program_ir($class_decl);

    my $optimizer = Chalk::Bootstrap::Optimizer::StructPromotion->new();
    my $schemas = $optimizer->analyze([
        { class_name => 'TestAccess', ir => $program }
    ]);

    my $rewritten = $optimizer->rewrite(
        [{ class_name => 'TestAccess', ir => $program }],
        $schemas,
    );

    # Walk rewritten IR to find FieldAccess (typed: StructFieldAccess)
    my $found_field_access = false;
    walk_ir($rewritten->[0]{ir}, sub($node) {
        if ($node isa Chalk::IR::Node::StructFieldAccess) {
            $found_field_access = true;
        }
    });

    ok($found_field_access, 'rewritten IR contains FieldAccess for read-site subscript');
}

done_testing;
