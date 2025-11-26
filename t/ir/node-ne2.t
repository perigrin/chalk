#!/usr/bin/env perl
# ABOUTME: Tests for simplified NE node (not equals)
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::NE2');
use Chalk::IR::Node::Constant2;

my $left = Chalk::IR::Node::Constant2->new(type => 'Int', value => 10);
my $right = Chalk::IR::Node::Constant2->new(type => 'Int', value => 5);

my $ne = Chalk::IR::Node::NE2->new(left => $left, right => $right);

is($ne->id, 'ne_const_Int_10_const_Int_5', 'Content-addressable ID');
is($ne->left, $left, 'Left operand accessible');
is($ne->right, $right, 'Right operand accessible');
is($ne->op, 'NE', 'Op is NE');

done_testing();
