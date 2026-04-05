# ABOUTME: Tests for Chalk::IR::Shim translation module.
# ABOUTME: Verifies that old-style Constructor class names map to typed IR nodes.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Shim;

my $f = Chalk::IR::NodeFactory->new();

# Ensure activation state is clean before each test file
Chalk::IR::Shim::reset_enabled();

# Helper: create a Constant node to represent a literal value in params
sub const_node($val) {
    return $f->make('Constant', value => $val, const_type => 'string', inputs => []);
}

# Helper: enable a class, run a block, then reset for isolation
sub with_enabled($class, $code) {
    Chalk::IR::Shim::enable_class($class);
    $code->();
    Chalk::IR::Shim::reset_enabled();
}

# ---- BinaryExpr translations ----

subtest 'BinaryExpr + maps to Add' => sub {
    with_enabled('BinaryExpr', sub {
        my $op    = const_node('+');
        my $left  = $f->make('Constant', value => 1, const_type => 'integer', inputs => []);
        my $right = $f->make('Constant', value => 2, const_type => 'integer', inputs => []);

        my $node = Chalk::IR::Shim::translate($f, 'BinaryExpr',
            op    => $op,
            left  => $left,
            right => $right,
        );

        ok(defined $node, 'BinaryExpr + returns a node');
        isa_ok($node, 'Chalk::IR::Node::Add', 'BinaryExpr + isa Add');
        is($node->class(), 'BinaryExpr', 'class() returns BinaryExpr compat_class');
        is($node->left()->id(), $left->id(), 'left field is set');
        is($node->right()->id(), $right->id(), 'right field is set');
    });
};

subtest 'BinaryExpr eq maps to StrEq' => sub {
    with_enabled('BinaryExpr', sub {
        my $op    = const_node('eq');
        my $left  = $f->make('Constant', value => 'a', const_type => 'string', inputs => []);
        my $right = $f->make('Constant', value => 'b', const_type => 'string', inputs => []);

        my $node = Chalk::IR::Shim::translate($f, 'BinaryExpr',
            op    => $op,
            left  => $left,
            right => $right,
        );

        ok(defined $node, 'BinaryExpr eq returns a node');
        isa_ok($node, 'Chalk::IR::Node::StrEq', 'BinaryExpr eq isa StrEq');
        is($node->class(), 'BinaryExpr', 'class() returns BinaryExpr compat_class');
    });
};

subtest 'BinaryExpr && maps to And' => sub {
    with_enabled('BinaryExpr', sub {
        my $op    = const_node('&&');
        my $left  = $f->make('Constant', value => 1, const_type => 'integer', inputs => []);
        my $right = $f->make('Constant', value => 0, const_type => 'integer', inputs => []);

        my $node = Chalk::IR::Shim::translate($f, 'BinaryExpr',
            op    => $op,
            left  => $left,
            right => $right,
        );

        ok(defined $node, 'BinaryExpr && returns a node');
        isa_ok($node, 'Chalk::IR::Node::And', 'BinaryExpr && isa And');
        is($node->class(), 'BinaryExpr', 'class() returns BinaryExpr compat_class');
    });
};

subtest 'BinaryExpr unknown op returns undef' => sub {
    with_enabled('BinaryExpr', sub {
        my $op    = const_node('???');
        my $left  = $f->make('Constant', value => 1, const_type => 'integer', inputs => []);
        my $right = $f->make('Constant', value => 2, const_type => 'integer', inputs => []);

        my $node = Chalk::IR::Shim::translate($f, 'BinaryExpr',
            op    => $op,
            left  => $left,
            right => $right,
        );

        is($node, undef, 'unknown BinaryExpr op returns undef');
    });
};

# ---- UnaryExpr translations ----

subtest 'UnaryExpr ! maps to Not' => sub {
    with_enabled('UnaryExpr', sub {
        my $op      = const_node('!');
        my $operand = $f->make('Constant', value => 1, const_type => 'integer', inputs => []);

        my $node = Chalk::IR::Shim::translate($f, 'UnaryExpr',
            op      => $op,
            operand => $operand,
        );

        ok(defined $node, 'UnaryExpr ! returns a node');
        isa_ok($node, 'Chalk::IR::Node::Not', 'UnaryExpr ! isa Not');
        is($node->class(), 'UnaryExpr', 'class() returns UnaryExpr compat_class');
        is($node->operand()->id(), $operand->id(), 'operand field is set');
    });
};

subtest 'UnaryExpr defined maps to Defined' => sub {
    with_enabled('UnaryExpr', sub {
        my $op      = const_node('defined');
        my $operand = $f->make('Constant', value => undef, const_type => 'undef', inputs => []);

        my $node = Chalk::IR::Shim::translate($f, 'UnaryExpr',
            op      => $op,
            operand => $operand,
        );

        ok(defined $node, 'UnaryExpr defined returns a node');
        isa_ok($node, 'Chalk::IR::Node::Defined', 'UnaryExpr defined isa Defined');
        is($node->class(), 'UnaryExpr', 'class() returns UnaryExpr compat_class');
    });
};

# ---- MethodCallExpr → Call(method) ----

subtest 'MethodCallExpr maps to Call(method)' => sub {
    with_enabled('MethodCallExpr', sub {
        my $invocant    = $f->make('Constant', value => '$self', const_type => 'string', inputs => []);
        my $method_name = const_node('process');
        my $args        = $f->make('Constant', value => '[]', const_type => 'string', inputs => []);

        my $node = Chalk::IR::Shim::translate($f, 'MethodCallExpr',
            invocant    => $invocant,
            method_name => $method_name,
            args        => $args,
        );

        ok(defined $node, 'MethodCallExpr returns a node');
        isa_ok($node, 'Chalk::IR::Node::Call', 'MethodCallExpr isa Call');
        is($node->dispatch_kind(), 'method', 'dispatch_kind is method');
        is($node->name(), 'process', 'name is method name');
        is($node->class(), 'MethodCallExpr', 'class() returns MethodCallExpr compat_class');
    });
};

# ---- BuiltinCall → Call(builtin) ----

subtest 'BuiltinCall maps to Call(builtin)' => sub {
    with_enabled('BuiltinCall', sub {
        my $name = const_node('push');
        my $args = $f->make('Constant', value => '[]', const_type => 'string', inputs => []);

        my $node = Chalk::IR::Shim::translate($f, 'BuiltinCall',
            name => $name,
            args => $args,
        );

        ok(defined $node, 'BuiltinCall returns a node');
        isa_ok($node, 'Chalk::IR::Node::Call', 'BuiltinCall isa Call');
        is($node->dispatch_kind(), 'builtin', 'dispatch_kind is builtin');
        is($node->name(), 'push', 'name is builtin name');
        is($node->class(), 'BuiltinCall', 'class() returns BuiltinCall compat_class');
    });
};

# ---- SubscriptExpr → Subscript ----

subtest 'SubscriptExpr maps to Subscript' => sub {
    with_enabled('SubscriptExpr', sub {
        my $target = $f->make('Constant', value => '@arr', const_type => 'string', inputs => []);
        my $index  = $f->make('Constant', value => 0,      const_type => 'integer', inputs => []);
        my $style  = const_node('array');

        my $node = Chalk::IR::Shim::translate($f, 'SubscriptExpr',
            target => $target,
            index  => $index,
            style  => $style,
        );

        ok(defined $node, 'SubscriptExpr returns a node');
        isa_ok($node, 'Chalk::IR::Node::Subscript', 'SubscriptExpr isa Subscript');
        is($node->class(), 'SubscriptExpr', 'class() returns SubscriptExpr compat_class');
    });
};

# ---- PostfixDerefExpr → PostfixDeref ----

subtest 'PostfixDerefExpr maps to PostfixDeref (Constant sigil)' => sub {
    with_enabled('PostfixDerefExpr', sub {
        my $target = $f->make('Constant', value => '$ref', const_type => 'string', inputs => []);
        my $sigil  = const_node('@');

        my $node = Chalk::IR::Shim::translate($f, 'PostfixDerefExpr',
            target => $target,
            sigil  => $sigil,
        );

        ok(defined $node, 'PostfixDerefExpr returns a node');
        isa_ok($node, 'Chalk::IR::Node::PostfixDeref', 'PostfixDerefExpr isa PostfixDeref');
        is($node->sigil(), '@', 'sigil is extracted from Constant node');
        is($node->class(), 'PostfixDerefExpr', 'class() returns PostfixDerefExpr compat_class');
    });
};

subtest 'PostfixDerefExpr maps to PostfixDeref (string sigil)' => sub {
    with_enabled('PostfixDerefExpr', sub {
        my $target = $f->make('Constant', value => '$ref', const_type => 'string', inputs => []);

        my $node = Chalk::IR::Shim::translate($f, 'PostfixDerefExpr',
            target => $target,
            sigil  => '%',
        );

        ok(defined $node, 'PostfixDerefExpr with string sigil returns a node');
        isa_ok($node, 'Chalk::IR::Node::PostfixDeref', 'isa PostfixDeref');
        is($node->sigil(), '%', 'sigil is used directly when a plain string');
    });
};

# ---- HashRefExpr → HashRef ----

subtest 'HashRefExpr maps to HashRef' => sub {
    with_enabled('HashRefExpr', sub {
        my $pairs = $f->make('Constant', value => '{}', const_type => 'string', inputs => []);

        my $node = Chalk::IR::Shim::translate($f, 'HashRefExpr',
            pairs => $pairs,
        );

        ok(defined $node, 'HashRefExpr returns a node');
        isa_ok($node, 'Chalk::IR::Node::HashRef', 'HashRefExpr isa HashRef');
        is($node->class(), 'HashRefExpr', 'class() returns HashRefExpr compat_class');
    });
};

# ---- VarDecl → VarDecl ----

subtest 'VarDecl maps to VarDecl' => sub {
    with_enabled('VarDecl', sub {
        my $variable    = $f->make('Constant', value => '$x', const_type => 'string', inputs => []);
        my $initializer = $f->make('Constant', value => 42,   const_type => 'integer', inputs => []);

        my $node = Chalk::IR::Shim::translate($f, 'VarDecl',
            variable    => $variable,
            initializer => $initializer,
        );

        ok(defined $node, 'VarDecl returns a node');
        isa_ok($node, 'Chalk::IR::Node::VarDecl', 'VarDecl isa VarDecl');
        is($node->class(), 'VarDecl', 'class() returns VarDecl compat_class');
    });
};

# ---- Structural types return undef ----

subtest 'Program returns undef (structural, not translated)' => sub {
    my $node = Chalk::IR::Shim::translate($f, 'Program');
    is($node, undef, 'Program returns undef');
};

subtest 'ClassDecl returns undef (structural, not translated)' => sub {
    my $node = Chalk::IR::Shim::translate($f, 'ClassDecl');
    is($node, undef, 'ClassDecl returns undef');
};

subtest 'MethodDecl returns undef (structural, not translated)' => sub {
    my $node = Chalk::IR::Shim::translate($f, 'MethodDecl');
    is($node, undef, 'MethodDecl returns undef');
};

subtest 'ReturnStmt returns undef (CFG, deferred to Phase 3b)' => sub {
    my $node = Chalk::IR::Shim::translate($f, 'ReturnStmt');
    is($node, undef, 'ReturnStmt returns undef');
};

subtest 'TernaryExpr returns undef (CFG lowering deferred)' => sub {
    my $node = Chalk::IR::Shim::translate($f, 'TernaryExpr');
    is($node, undef, 'TernaryExpr returns undef');
};

# ---- BNF types return undef ----

subtest 'Symbol returns undef (BNF type, not translated)' => sub {
    my $node = Chalk::IR::Shim::translate($f, 'Symbol');
    is($node, undef, 'Symbol returns undef');
};

subtest 'Expression returns undef (BNF type, not translated)' => sub {
    my $node = Chalk::IR::Shim::translate($f, 'Expression');
    is($node, undef, 'Expression returns undef');
};

subtest 'Rule returns undef (BNF type, not translated)' => sub {
    my $node = Chalk::IR::Shim::translate($f, 'Rule');
    is($node, undef, 'Rule returns undef');
};

done_testing();
