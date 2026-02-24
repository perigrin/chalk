# ABOUTME: Tests for Tier C IR node types used by runtime method logic.
# ABOUTME: Validates VarDecl, BinaryExpr, MethodCallExpr, etc. via NodeFactory.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Helper: make a string Constant
my sub c($val) {
    return $factory->make('Constant', const_type => 'string', value => $val);
}

# ============================================================
# 1. VarDecl — my $x = expr
# ============================================================

{
    my $var = c('$x');
    my $init = c('hello');
    my $node = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $var,
        initializer => $init,
    );
    ok(defined $node, 'VarDecl: created');
    is($node->class(), 'VarDecl', 'VarDecl: class');
    is($node->inputs()->[0]->value(), '$x', 'VarDecl: variable');
    is($node->inputs()->[1]->value(), 'hello', 'VarDecl: initializer');

    # VarDecl without initializer
    my $bare = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => c('$y'),
        initializer => undef,
    );
    ok(defined $bare, 'VarDecl: bare created');
    is($bare->inputs()->[1], undef, 'VarDecl: no initializer');
}

# ============================================================
# 2. BinaryExpr — $a op $b
# ============================================================

{
    my $node = $factory->make('Constructor',
        class => 'BinaryExpr',
        op    => c('.'),
        left  => c('$a'),
        right => c('$b'),
    );
    ok(defined $node, 'BinaryExpr: created');
    is($node->class(), 'BinaryExpr', 'BinaryExpr: class');
    is($node->inputs()->[0]->value(), '.', 'BinaryExpr: op');
    is($node->inputs()->[1]->value(), '$a', 'BinaryExpr: left');
    is($node->inputs()->[2]->value(), '$b', 'BinaryExpr: right');
}

# ============================================================
# 5. UnaryExpr — !$x, defined($x)
# ============================================================

{
    my $node = $factory->make('Constructor',
        class   => 'UnaryExpr',
        op      => c('!'),
        operand => c('$x'),
    );
    ok(defined $node, 'UnaryExpr: created');
    is($node->class(), 'UnaryExpr', 'UnaryExpr: class');
    is($node->inputs()->[0]->value(), '!', 'UnaryExpr: op');
    is($node->inputs()->[1]->value(), '$x', 'UnaryExpr: operand');
}

# ============================================================
# 6. CompoundAssign — $x .= $y
# ============================================================

{
    my $node = $factory->make('Constructor',
        class  => 'CompoundAssign',
        op     => c('.='),
        target => c('$x'),
        value  => c('$y'),
    );
    ok(defined $node, 'CompoundAssign: created');
    is($node->class(), 'CompoundAssign', 'CompoundAssign: class');
    is($node->inputs()->[0]->value(), '.=', 'CompoundAssign: op');
    is($node->inputs()->[1]->value(), '$x', 'CompoundAssign: target');
    is($node->inputs()->[2]->value(), '$y', 'CompoundAssign: value');
}

# ============================================================
# 7. MethodCallExpr — $self->method($args)
# ============================================================

{
    my $node = $factory->make('Constructor',
        class       => 'MethodCallExpr',
        invocant    => c('$self'),
        method_name => c('foo'),
        args        => [c('$x')],
    );
    ok(defined $node, 'MethodCallExpr: created');
    is($node->class(), 'MethodCallExpr', 'MethodCallExpr: class');
    is($node->inputs()->[0]->value(), '$self', 'MethodCallExpr: invocant');
    is($node->inputs()->[1]->value(), 'foo', 'MethodCallExpr: method_name');
    is(ref $node->inputs()->[2], 'ARRAY', 'MethodCallExpr: args is array');
}

# ============================================================
# 8. SubscriptExpr — $arr->[$i], $hash->{$key}
# ============================================================

{
    my $node = $factory->make('Constructor',
        class  => 'SubscriptExpr',
        target => c('$arr'),
        index  => c('$i'),
        style  => c('array'),
    );
    ok(defined $node, 'SubscriptExpr: created');
    is($node->class(), 'SubscriptExpr', 'SubscriptExpr: class');
    is($node->inputs()->[0]->value(), '$arr', 'SubscriptExpr: target');
    is($node->inputs()->[1]->value(), '$i', 'SubscriptExpr: index');
    is($node->inputs()->[2]->value(), 'array', 'SubscriptExpr: style');
}

# ============================================================
# 9. PostfixDerefExpr — $ref->@*
# ============================================================

{
    my $node = $factory->make('Constructor',
        class  => 'PostfixDerefExpr',
        target => c('$ref'),
        sigil  => c('@'),
    );
    ok(defined $node, 'PostfixDerefExpr: created');
    is($node->class(), 'PostfixDerefExpr', 'PostfixDerefExpr: class');
    is($node->inputs()->[0]->value(), '$ref', 'PostfixDerefExpr: target');
    is($node->inputs()->[1]->value(), '@', 'PostfixDerefExpr: sigil');
}

# ============================================================
# 10. TernaryExpr — $x ? $y : $z
# ============================================================

{
    my $node = $factory->make('Constructor',
        class      => 'TernaryExpr',
        condition  => c('$x'),
        true_expr  => c('$y'),
        false_expr => c('$z'),
    );
    ok(defined $node, 'TernaryExpr: created');
    is($node->class(), 'TernaryExpr', 'TernaryExpr: class');
    is($node->inputs()->[0]->value(), '$x', 'TernaryExpr: condition');
    is($node->inputs()->[1]->value(), '$y', 'TernaryExpr: true_expr');
    is($node->inputs()->[2]->value(), '$z', 'TernaryExpr: false_expr');
}

# ============================================================
# 11. HashRefExpr — { key => val }
# ============================================================

{
    my $node = $factory->make('Constructor',
        class => 'HashRefExpr',
        pairs => [c('key'), c('val')],
    );
    ok(defined $node, 'HashRefExpr: created');
    is($node->class(), 'HashRefExpr', 'HashRefExpr: class');
    is(ref $node->inputs()->[0], 'ARRAY', 'HashRefExpr: pairs is array');
    is(scalar $node->inputs()->[0]->@*, 2, 'HashRefExpr: 2 elements');
}

# ============================================================
# 12. ArrayRefExpr — [1, 2, 3]
# ============================================================

{
    my $node = $factory->make('Constructor',
        class    => 'ArrayRefExpr',
        elements => [c('1'), c('2')],
    );
    ok(defined $node, 'ArrayRefExpr: created');
    is($node->class(), 'ArrayRefExpr', 'ArrayRefExpr: class');
    is(ref $node->inputs()->[0], 'ARRAY', 'ArrayRefExpr: elements is array');
}

# ============================================================
# 13. AnonSubExpr — sub ($x) { ... }
# ============================================================

{
    my $node = $factory->make('Constructor',
        class  => 'AnonSubExpr',
        params => [c('$x')],
        body   => [c('return')],
    );
    ok(defined $node, 'AnonSubExpr: created');
    is($node->class(), 'AnonSubExpr', 'AnonSubExpr: class');
    is(ref $node->inputs()->[0], 'ARRAY', 'AnonSubExpr: params is array');
    is(ref $node->inputs()->[1], 'ARRAY', 'AnonSubExpr: body is array');
}

# ============================================================
# 14. RegexMatch — $x =~ /pattern/flags
# ============================================================

{
    my $node = $factory->make('Constructor',
        class   => 'RegexMatch',
        target  => c('$x'),
        pattern => c('/foo/'),
        flags   => c(''),
    );
    ok(defined $node, 'RegexMatch: created');
    is($node->class(), 'RegexMatch', 'RegexMatch: class');
    is($node->inputs()->[0]->value(), '$x', 'RegexMatch: target');
    is($node->inputs()->[1]->value(), '/foo/', 'RegexMatch: pattern');
}

# ============================================================
# 15. RegexSubst — $x =~ s/pat/repl/flags
# ============================================================

{
    my $node = $factory->make('Constructor',
        class       => 'RegexSubst',
        target      => c('$x'),
        pattern     => c('foo'),
        replacement => c('bar'),
        flags       => c('g'),
    );
    ok(defined $node, 'RegexSubst: created');
    is($node->class(), 'RegexSubst', 'RegexSubst: class');
    is($node->inputs()->[0]->value(), '$x', 'RegexSubst: target');
    is($node->inputs()->[1]->value(), 'foo', 'RegexSubst: pattern');
    is($node->inputs()->[2]->value(), 'bar', 'RegexSubst: replacement');
    is($node->inputs()->[3]->value(), 'g', 'RegexSubst: flags');
}

# ============================================================
# 16. BuiltinCall — push(@arr, $x), join(",", @arr), etc.
# ============================================================

{
    my $node = $factory->make('Constructor',
        class => 'BuiltinCall',
        name  => c('push'),
        args  => [c('@arr'), c('$x')],
    );
    ok(defined $node, 'BuiltinCall: created');
    is($node->class(), 'BuiltinCall', 'BuiltinCall: class');
    is($node->inputs()->[0]->value(), 'push', 'BuiltinCall: name');
    is(ref $node->inputs()->[1], 'ARRAY', 'BuiltinCall: args is array');
}

# ============================================================
# 19. BacktickExpr — `command`
# ============================================================

{
    my $node = $factory->make('Constructor',
        class   => 'BacktickExpr',
        command => c('ls -la'),
    );
    ok(defined $node, 'BacktickExpr: created');
    is($node->class(), 'BacktickExpr', 'BacktickExpr: class');
    is($node->inputs()->[0]->value(), 'ls -la', 'BacktickExpr: command');
}

# ============================================================
# 20. FieldDecl with default_value (backward-compatible)
# ============================================================

{
    # Old-style: 2 inputs
    my $old = $factory->make('Constructor',
        class         => 'FieldDecl',
        name          => c('$x'),
        attributes    => [],
        default_value => undef,
    );
    ok(defined $old, 'FieldDecl: old-style with undef default');
    is($old->inputs()->[2], undef, 'FieldDecl: third input is undef');

    # New-style: with default
    my $with_default = $factory->make('Constructor',
        class         => 'FieldDecl',
        name          => c('$ops'),
        attributes    => [],
        default_value => $factory->make('Constructor',
            class    => 'ArrayRefExpr',
            elements => [],
        ),
    );
    ok(defined $with_default, 'FieldDecl: with default_value');
    is($with_default->inputs()->[2]->class(), 'ArrayRefExpr',
        'FieldDecl: default_value is ArrayRefExpr');
}

# ============================================================
# 21. Hash consing works for new types
# ============================================================

{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $f = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $c1 = $f->make('Constant', const_type => 'string', value => 'test');
    my $c2 = $f->make('Constant', const_type => 'string', value => 'test');
    is($c1, $c2, 'Hash consing: same Constant returns same object');

    my $n1 = $f->make('Constructor', class => 'VarDecl',
        variable => $c1, initializer => undef);
    my $n2 = $f->make('Constructor', class => 'VarDecl',
        variable => $c2, initializer => undef);
    is($n1, $n2, 'Hash consing: same VarDecl returns same object');
}

done_testing();
