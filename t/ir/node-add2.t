#!/usr/bin/env perl
# ABOUTME: Tests for simplified Add node
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Add2');
use Chalk::IR::Node::Constant2;

my $left = Chalk::IR::Node::Constant2->new(type => 'Int', value => 10);
my $right = Chalk::IR::Node::Constant2->new(type => 'Int', value => 5);

my $add = Chalk::IR::Node::Add2->new(left => $left, right => $right);

is($add->id, 'add_const_Int_10_const_Int_5', 'Content-addressable ID');
is($add->left, $left, 'Left operand accessible');
is($add->right, $right, 'Right operand accessible');
is($add->op, 'Add', 'Op is Add');

done_testing();
