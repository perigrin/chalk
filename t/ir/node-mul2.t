#!/usr/bin/env perl
# ABOUTME: Tests for simplified Mul node
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Mul2');
use Chalk::IR::Node::Constant2;

my $left = Chalk::IR::Node::Constant2->new(type => 'Int', value => 10);
my $right = Chalk::IR::Node::Constant2->new(type => 'Int', value => 5);

my $mul = Chalk::IR::Node::Mul2->new(left => $left, right => $right);

is($mul->id, 'mul_const_Int_10_const_Int_5', 'Content-addressable ID');
is($mul->left, $left, 'Left operand accessible');
is($mul->right, $right, 'Right operand accessible');
is($mul->op, 'Mul', 'Op is Mul');

done_testing();
