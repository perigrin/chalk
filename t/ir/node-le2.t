#!/usr/bin/env perl
# ABOUTME: Tests for simplified LE node (less than or equal)
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::LE2');
use Chalk::IR::Node::Constant2;

my $left = Chalk::IR::Node::Constant2->new(type => 'Int', value => 10);
my $right = Chalk::IR::Node::Constant2->new(type => 'Int', value => 5);

my $le = Chalk::IR::Node::LE2->new(left => $left, right => $right);

is($le->id, 'le_const_Int_10_const_Int_5', 'Content-addressable ID');
is($le->left, $left, 'Left operand accessible');
is($le->right, $right, 'Right operand accessible');
is($le->op, 'LE', 'Op is LE');

done_testing();
