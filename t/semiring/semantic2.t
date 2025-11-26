#!/usr/bin/env perl
# ABOUTME: Tests for simplified Semantic semiring
# ABOUTME: Validates scope in env and rule dispatch
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::Semiring::Semantic2');
use Chalk::IR::Node::Scope2;

# Test construction with default scope
my $sem = Chalk::Semiring::Semantic2->new();
ok($sem->env->{scope}, 'Default scope created');
isa_ok($sem->env->{scope}, 'Chalk::IR::Node::Scope2');

# Test construction with provided scope
my $scope = Chalk::IR::Node::Scope2->new();
my $sem2 = Chalk::Semiring::Semantic2->new(env => { scope => $scope });
is($sem2->env->{scope}, $scope, 'Provided scope used');

done_testing();
