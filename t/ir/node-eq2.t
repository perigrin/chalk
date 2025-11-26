#!/usr/bin/env perl
# ABOUTME: Tests for simplified EQ node (equals)
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::EQ2');
use Chalk::IR::Node::Constant2;

my $left = Chalk::IR::Node::Constant2->new(type => 'Int', value => 10);
my $right = Chalk::IR::Node::Constant2->new(type => 'Int', value => 5);

my $eq = Chalk::IR::Node::EQ2->new(left => $left, right => $right);

is($eq->id, 'eq_const_Int_10_const_Int_5', 'Content-addressable ID');
is($eq->left, $left, 'Left operand accessible');
is($eq->right, $right, 'Right operand accessible');
is($eq->op, 'EQ', 'Op is EQ');

done_testing();
