#!/usr/bin/env perl
# ABOUTME: Tests for simplified LT node (less than)
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::LT2');
use Chalk::IR::Node::Constant2;

my $left = Chalk::IR::Node::Constant2->new(type => 'Int', value => 10);
my $right = Chalk::IR::Node::Constant2->new(type => 'Int', value => 5);

my $lt = Chalk::IR::Node::LT2->new(left => $left, right => $right);

is($lt->id, 'lt_const_Int_10_const_Int_5', 'Content-addressable ID');
is($lt->left, $left, 'Left operand accessible');
is($lt->right, $right, 'Right operand accessible');
is($lt->op, 'LT', 'Op is LT');

done_testing();
