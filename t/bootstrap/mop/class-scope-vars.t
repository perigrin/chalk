# ABOUTME: MOP unit tests for Chalk::MOP::Class.declare_class_scope_var.
# ABOUTME: Verifies class-scope `my $x = ...;` declarations are recorded and bound in $scope.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::MOP;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::Constant;

# Helper: construct a synthetic VarDecl(name => '$VAR', init => undef).
# id/inputs are honest — Constant for the name; control/init undef
# because this is a hand-built test fixture, not a parser-derived node.
my $id_counter = 0;
sub make_vardecl ($var_name) {
    my $name_const = Chalk::IR::Node::Constant->new(
        id    => 'c_' . $id_counter++,
        inputs => [],
        const_type => 'variable',
        value      => $var_name,
    );
    return Chalk::IR::Node::VarDecl->new(
        id     => 'vd_' . $id_counter++,
        inputs => [undef, $name_const, undef],
    );
}

# Test 1: empty class has empty class_scope_vars + empty scope
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Foo');
    my @empty = $cls->class_scope_vars;
    is(scalar @empty, 0,
        'fresh class has zero class_scope_vars');
    ok(defined $cls->scope, 'fresh class has defined scope');
    is($cls->scope->lookup('$missing'), undef,
        'fresh scope returns undef for unknown name');
}

# Test 2: single declare records the VarDecl and binds in scope
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Foo');
    my $vd  = make_vardecl('$ZERO');

    my $returned = $cls->declare_class_scope_var($vd);

    is($returned, $vd, 'declare_class_scope_var returns the node passed in');

    my @list = $cls->class_scope_vars;
    is(scalar @list, 1, 'class_scope_vars has 1 entry after one declare');
    is($list[0], $vd, 'class_scope_vars entry is the same VarDecl object');

    is($cls->scope->lookup('$ZERO'), $vd,
        'scope->lookup($ZERO) returns the VarDecl');
}

# Test 3: multiple declarations preserve insertion order in the list,
# and all bindings are reachable via scope->lookup.
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Foo');
    my $a = make_vardecl('$A');
    my $b = make_vardecl('$B');
    my $c = make_vardecl('$C');

    $cls->declare_class_scope_var($a);
    $cls->declare_class_scope_var($b);
    $cls->declare_class_scope_var($c);

    my @list = $cls->class_scope_vars;
    is(scalar @list, 3, 'class_scope_vars has 3 entries');
    is($list[0], $a, 'insertion order [0] is $A');
    is($list[1], $b, 'insertion order [1] is $B');
    is($list[2], $c, 'insertion order [2] is $C');

    is($cls->scope->lookup('$A'), $a, 'scope->lookup($A) returns $a');
    is($cls->scope->lookup('$B'), $b, 'scope->lookup($B) returns $b');
    is($cls->scope->lookup('$C'), $c, 'scope->lookup($C) returns $c');
}

# Test 4: scope is immutable copy-on-write — each declare returns a new Scope.
# (We don't expose the intermediate scope to callers, but the field itself
# must follow Scope's contract: $scope = $scope->define(...).)
# This test ensures the scope-after-3-declarations contains all 3 bindings;
# if declare_class_scope_var forgot to assign back, only the last would be
# visible.
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Foo');
    $cls->declare_class_scope_var(make_vardecl('$A'));
    $cls->declare_class_scope_var(make_vardecl('$B'));

    ok(defined $cls->scope->lookup('$A'),
        '$A still visible after later declare ($scope reassignment works)');
    ok(defined $cls->scope->lookup('$B'),
        '$B visible after its own declare');
}

done_testing();
