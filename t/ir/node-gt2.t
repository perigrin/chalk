#!/usr/bin/env perl
# ABOUTME: Tests for simplified GT node (greater than)
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::GT2');
use Chalk::IR::Node::Constant2;

my $left = Chalk::IR::Node::Constant2->new(type => 'Int', value => 10);
my $right = Chalk::IR::Node::Constant2->new(type => 'Int', value => 5);

my $gt = Chalk::IR::Node::GT2->new(left => $left, right => $right);

is($gt->id, 'gt_const_Int_10_const_Int_5', 'Content-addressable ID');
is($gt->left, $left, 'Left operand accessible');
is($gt->right, $right, 'Right operand accessible');
is($gt->op, 'GT', 'Op is GT');

done_testing();
