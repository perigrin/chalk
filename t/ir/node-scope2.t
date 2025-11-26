#!/usr/bin/env perl
# ABOUTME: Tests for simplified Scope node
# ABOUTME: SSA bindings and control tracking
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Scope2');
use Chalk::IR::Node::Start2;
use Chalk::IR::Node::Constant2;

my $scope = Chalk::IR::Node::Scope2->new();

# Control tracking
my $start = Chalk::IR::Node::Start2->new(label => 'main');
$scope->set_current_control($start);
is($scope->current_control, $start, 'Current control set');

# Variable binding
my $value = Chalk::IR::Node::Constant2->new(type => 'Int', value => 42);
$scope->define('x', $value);
is($scope->get('x'), $value, 'Variable bound');

# Snapshot/restore
my $snapshot = $scope->snapshot();
my $new_value = Chalk::IR::Node::Constant2->new(type => 'Int', value => 99);
$scope->define('x', $new_value);
is($scope->get('x'), $new_value, 'Variable rebound');

$scope->restore($snapshot);
is($scope->get('x'), $value, 'Snapshot restored');

done_testing();
