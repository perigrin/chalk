#!/usr/bin/env perl
# ABOUTME: Test Scope class for lexical variable scoping in semantic context
# ABOUTME: Verify scope creation, variable binding, lookup, and lexical chaining
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More;
use Chalk::Semantic::Scope;

# Test 1: Create empty scope
{
    my $scope = Chalk::Semantic::Scope->new();

    isa_ok($scope, 'Chalk::Semantic::Scope', 'Empty scope created');
    is($scope->parent, undef, 'Empty scope has no parent');
}

# Test 2: Bind and lookup variable in scope
{
    my $scope = Chalk::Semantic::Scope->new();

    $scope->bind('x', 42);
    is($scope->lookup('x'), 42, 'Variable lookup works');

    $scope->bind('name', 'test');
    is($scope->lookup('name'), 'test', 'String variable lookup works');
}

# Test 3: Undefined variable lookup
{
    my $scope = Chalk::Semantic::Scope->new();

    is($scope->lookup('undefined_var'), undef, 'Undefined variable returns undef');
}

# Test 4: Variable shadowing
{
    my $scope = Chalk::Semantic::Scope->new();

    $scope->bind('x', 1);
    is($scope->lookup('x'), 1, 'Initial binding');

    $scope->bind('x', 2);
    is($scope->lookup('x'), 2, 'Rebinding shadows previous value');
}

# Test 5: Nested scopes with parent
{
    my $parent = Chalk::Semantic::Scope->new();
    $parent->bind('x', 'parent_value');

    my $child = Chalk::Semantic::Scope->new(parent => $parent);

    is($child->parent, $parent, 'Child has parent reference');
    is($child->lookup('x'), 'parent_value', 'Child can lookup parent variables');
}

# Test 6: Nested scope shadowing
{
    my $parent = Chalk::Semantic::Scope->new();
    $parent->bind('x', 'parent');
    $parent->bind('y', 'parent_y');

    my $child = Chalk::Semantic::Scope->new(parent => $parent);
    $child->bind('x', 'child');

    is($child->lookup('x'), 'child', 'Child shadows parent variable');
    is($child->lookup('y'), 'parent_y', 'Child inherits non-shadowed parent variable');
    is($parent->lookup('x'), 'parent', 'Parent variable unchanged');
}

# Test 7: Multiple nesting levels
{
    my $grandparent = Chalk::Semantic::Scope->new();
    $grandparent->bind('a', 1);

    my $parent = Chalk::Semantic::Scope->new(parent => $grandparent);
    $parent->bind('b', 2);

    my $child = Chalk::Semantic::Scope->new(parent => $parent);
    $child->bind('c', 3);

    is($child->lookup('a'), 1, 'Lookup through grandparent');
    is($child->lookup('b'), 2, 'Lookup through parent');
    is($child->lookup('c'), 3, 'Lookup in current scope');
}

# Test 8: has_binding() method
{
    my $scope = Chalk::Semantic::Scope->new();
    $scope->bind('x', 42);

    ok($scope->has_binding('x'), 'has_binding returns true for bound variable');
    ok(!$scope->has_binding('y'), 'has_binding returns false for unbound variable');
}

# Test 9: has_local_binding() - doesn't check parent
{
    my $parent = Chalk::Semantic::Scope->new();
    $parent->bind('x', 'parent');

    my $child = Chalk::Semantic::Scope->new(parent => $parent);
    $child->bind('y', 'child');

    ok($child->has_local_binding('y'), 'has_local_binding finds local variable');
    ok(!$child->has_local_binding('x'), 'has_local_binding does not find parent variable');
}

# Test 10: get_bindings() returns local bindings
{
    my $scope = Chalk::Semantic::Scope->new();
    $scope->bind('x', 1);
    $scope->bind('y', 2);

    my $bindings = $scope->get_bindings();
    is(ref($bindings), 'HASH', 'get_bindings returns hash reference');
    is($bindings->{x}, 1, 'Binding x present');
    is($bindings->{y}, 2, 'Binding y present');
}

done_testing();
