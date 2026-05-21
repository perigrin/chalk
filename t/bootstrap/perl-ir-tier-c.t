# ABOUTME: Tests for Tier C IR node types used by runtime method logic.
# ABOUTME: Validates VarDecl, BinaryExpr, MethodCallExpr, etc. via NodeFactory.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::IR::NodeFactory;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
my $typed   = Chalk::IR::NodeFactory->new;

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
    my $node = $typed->make('VarDecl',
        inputs       => [undef, $var, $init],
        compat_class => 'VarDecl',
    );
    ok(defined $node, 'VarDecl: created');
    is($node->class(), 'VarDecl', 'VarDecl: class');
    is($node->inputs()->[1]->value(), '$x', 'VarDecl: variable');
    is($node->inputs()->[2]->value(), 'hello', 'VarDecl: initializer');

    # VarDecl without initializer
    my $bare = $typed->make('VarDecl',
        inputs       => [undef, c('$y'), undef],
        compat_class => 'VarDecl',
    );
    ok(defined $bare, 'VarDecl: bare created');
    is($bare->inputs()->[2], undef, 'VarDecl: no initializer');
}

# ============================================================
# 2. BinaryExpr — $a op $b
# ============================================================

{
    my $op    = c('.');
    my $left  = c('$a');
    my $right = c('$b');
    my $node  = $typed->make('Concat',
        inputs       => [$op, $left, $right],
        left         => $left,
        right        => $right,
        compat_class => 'BinaryExpr',
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
    my $op      = c('!');
    my $operand = c('$x');
    my $node    = $typed->make('Not',
        inputs       => [$op, $operand],
        operand      => $operand,
        compat_class => 'UnaryExpr',
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
    my $op = c('.=');
    my $node = $typed->make('CompoundAssign',
        op           => $op->value(),
        inputs       => [$op, c('$x'), c('$y')],
        compat_class => 'CompoundAssign',
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
    my $method_name = c('foo');
    my $node = $typed->make('Call',
        dispatch_kind => 'method',
        name          => $method_name->value(),
        inputs        => [c('$self'), $method_name, [c('$x')]],
        compat_class  => 'MethodCallExpr',
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
    my $node = $typed->make('Subscript',
        inputs       => [c('$arr'), c('$i'), c('array')],
        compat_class => 'SubscriptExpr',
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
    my $target = c('$ref');
    my $sigil  = c('@');
    my $node = $typed->make('PostfixDeref',
        sigil        => $sigil->value(),
        inputs       => [$target, $sigil],
        compat_class => 'PostfixDerefExpr',
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
    my $node = $typed->make('TernaryExpr',
        inputs       => [c('$x'), c('$y'), c('$z')],
        compat_class => 'TernaryExpr',
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
    my $node = $typed->make('HashRef',
        inputs       => [[c('key'), c('val')]],
        compat_class => 'HashRefExpr',
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
    my $node = $typed->make('ArrayRef',
        inputs       => [[c('1'), c('2')]],
        compat_class => 'ArrayRefExpr',
    );
    ok(defined $node, 'ArrayRefExpr: created');
    is($node->class(), 'ArrayRefExpr', 'ArrayRefExpr: class');
    is(ref $node->inputs()->[0], 'ARRAY', 'ArrayRefExpr: elements is array');
}

# ============================================================
# 13. AnonSubExpr — sub ($x) { ... }
# ============================================================

{
    my $node = $typed->make('AnonSub',
        inputs       => [[c('$x')], [c('return')]],
        compat_class => 'AnonSubExpr',
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
    my $flags = c('');
    my $node = $typed->make('RegexMatch',
        flags        => $flags->value(),
        inputs       => [c('$x'), c('/foo/'), $flags],
        compat_class => 'RegexMatch',
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
    my $flags = c('g');
    my $node = $typed->make('RegexSubst',
        flags        => $flags->value(),
        inputs       => [c('$x'), c('foo'), c('bar'), $flags],
        compat_class => 'RegexSubst',
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
    my $name = c('push');
    my $node = $typed->make('Call',
        dispatch_kind => 'builtin',
        name          => $name->value(),
        inputs        => [$name, [c('@arr'), c('$x')]],
        compat_class  => 'BuiltinCall',
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
    my $node = $typed->make('BacktickExpr',
        inputs       => [c('ls -la')],
        compat_class => 'BacktickExpr',
    );
    ok(defined $node, 'BacktickExpr: created');
    is($node->class(), 'BacktickExpr', 'BacktickExpr: class');
    is($node->inputs()->[0]->value(), 'ls -la', 'BacktickExpr: command');
}

# ============================================================
# 20. FieldDecl with default_value (backward-compatible)
# ============================================================
# FieldDecl is not currently in the Shim translation table and has no
# typed Chalk::IR::Node::* equivalent. Skip until it is migrated.

SKIP: {
    skip 'FieldDecl has no typed equivalent yet', 4;
}

# ============================================================
# 21. Hash consing works for new types
# ============================================================

{
    my $t  = Chalk::IR::NodeFactory->new;
    my $c1 = $t->make('Constant', const_type => 'string', value => 'test');
    my $c2 = $t->make('Constant', const_type => 'string', value => 'test');
    is($c1, $c2, 'Hash consing: same Constant returns same object');

    my $n1 = $t->make('VarDecl',
        inputs       => [undef, $c1, undef],
        compat_class => 'VarDecl',
    );
    my $n2 = $t->make('VarDecl',
        inputs       => [undef, $c2, undef],
        compat_class => 'VarDecl',
    );
    is($n1, $n2, 'Hash consing: same VarDecl returns same object');
}

done_testing();
