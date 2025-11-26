#!/usr/bin/env perl
# ABOUTME: Tests for simplified Div node
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Div2');
use Chalk::IR::Node::Constant2;

my $left = Chalk::IR::Node::Constant2->new(type => 'Int', value => 10);
my $right = Chalk::IR::Node::Constant2->new(type => 'Int', value => 5);

my $div = Chalk::IR::Node::Div2->new(left => $left, right => $right);

is($div->id, 'div_const_Int_10_const_Int_5', 'Content-addressable ID');
is($div->left, $left, 'Left operand accessible');
is($div->right, $right, 'Right operand accessible');
is($div->op, 'Div', 'Op is Div');

done_testing();
