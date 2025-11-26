#!/usr/bin/env perl
# ABOUTME: Tests for simplified GE node (greater than or equal)
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::GE2');
use Chalk::IR::Node::Constant2;

my $left = Chalk::IR::Node::Constant2->new(type => 'Int', value => 10);
my $right = Chalk::IR::Node::Constant2->new(type => 'Int', value => 5);

my $ge = Chalk::IR::Node::GE2->new(left => $left, right => $right);

is($ge->id, 'ge_const_Int_10_const_Int_5', 'Content-addressable ID');
is($ge->left, $left, 'Left operand accessible');
is($ge->right, $right, 'Right operand accessible');
is($ge->op, 'GE', 'Op is GE');

done_testing();
