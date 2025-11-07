#!/usr/bin/env perl
# ABOUTME: Test CEK interpreter Environment class with discrete contexts
# ABOUTME: Tests node context, variable context, and context isolation
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 15;
use Chalk::Interpreter::Environment;

# Test module can be loaded
use_ok('Chalk::Interpreter::Environment');

# Test Environment can be instantiated
my $env = Chalk::Interpreter::Environment->new();
ok(defined $env, 'Environment instantiated');
isa_ok($env, 'Chalk::Interpreter::Environment', 'correct class');

# Test node context operations
$env->set_node('node_1', 42);
is($env->lookup_node('node_1'), 42, 'node context stores and retrieves value');
is($env->lookup_node('node_2'), undef, 'node context returns undef for unknown node');

# Test variable context operations
$env->set_variable('x', 100);
is($env->lookup_variable('x'), 100, 'variable context stores and retrieves value');
is($env->lookup_variable('y'), undef, 'variable context returns undef for unknown variable');

# Test context isolation - node and variable namespaces are separate
$env->set_node('foo', 'node_value');
$env->set_variable('foo', 'var_value');
is($env->lookup_node('foo'), 'node_value', 'node context isolated from variable context');
is($env->lookup_variable('foo'), 'var_value', 'variable context isolated from node context');

# Test immutability - creating new environment doesn't affect old one
my $env2 = $env->extend_node('node_3', 99);
is($env2->lookup_node('node_3'), 99, 'new environment has new binding');
is($env->lookup_node('node_3'), undef, 'old environment unchanged (immutability)');

# Test that extended environment still has old bindings
is($env2->lookup_node('node_1'), 42, 'extended environment chains to parent');
is($env2->lookup_variable('x'), 100, 'extended environment preserves variable context');

# Test variable extension
my $env3 = $env->extend_variable('z', 200);
is($env3->lookup_variable('z'), 200, 'extended variable binding');
is($env->lookup_variable('z'), undef, 'original environment unchanged');
