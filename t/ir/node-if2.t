#!/usr/bin/env perl
# ABOUTME: Tests for simplified If node (conditional branch)
# ABOUTME: Control flow node that branches based on condition
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::If2');
use Chalk::IR::Node::Start2;
use Chalk::IR::Node::Constant2;

my $start = Chalk::IR::Node::Start2->new(label => 'main');
my $condition = Chalk::IR::Node::Constant2->new(type => 'Bool', value => 1);

my $if = Chalk::IR::Node::If2->new(
    control   => $start,
    condition => $condition,
);

is($if->id, 'if_start_main_const_Bool_1', 'Content-addressable ID');
is($if->control, $start, 'Control predecessor accessible');
is($if->condition, $condition, 'Condition node accessible');
is($if->op, 'If', 'Op is If');

done_testing();
