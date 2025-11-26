#!/usr/bin/env perl
# ABOUTME: Tests for simplified Sub node
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Sub2');
use Chalk::IR::Node::Constant2;

my $left = Chalk::IR::Node::Constant2->new(type => 'Int', value => 10);
my $right = Chalk::IR::Node::Constant2->new(type => 'Int', value => 5);

my $sub = Chalk::IR::Node::Sub2->new(left => $left, right => $right);

is($sub->id, 'sub_const_Int_10_const_Int_5', 'Content-addressable ID');
is($sub->left, $left, 'Left operand accessible');
is($sub->right, $right, 'Right operand accessible');
is($sub->op, 'Sub', 'Op is Sub');

done_testing();
