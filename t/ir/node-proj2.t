#!/usr/bin/env perl
# ABOUTME: Tests for simplified Proj node (projection from If)
# ABOUTME: Extracts control path from conditional branch
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Proj2');
use Chalk::IR::Node::If2;
use Chalk::IR::Node::Start2;
use Chalk::IR::Node::Constant2;

my $start = Chalk::IR::Node::Start2->new(label => 'main');
my $condition = Chalk::IR::Node::Constant2->new(type => 'Bool', value => 1);
my $if = Chalk::IR::Node::If2->new(
    control   => $start,
    condition => $condition,
);

# Test true branch projection
my $proj_true = Chalk::IR::Node::Proj2->new(
    source => $if,
    index  => 0,
    label  => "IfTrue",
);

is($proj_true->id, 'proj_if_start_main_const_Bool_1_0', 'Content-addressable ID for true branch');
is($proj_true->source, $if, 'Source If node accessible');
is($proj_true->index, 0, 'Index is 0 for true branch');
is($proj_true->label, 'IfTrue', 'Label is IfTrue');
is($proj_true->op, 'Proj', 'Op is Proj');

# Test false branch projection
my $proj_false = Chalk::IR::Node::Proj2->new(
    source => $if,
    index  => 1,
    label  => "IfFalse",
);

is($proj_false->id, 'proj_if_start_main_const_Bool_1_1', 'Content-addressable ID for false branch');
is($proj_false->source, $if, 'Source If node accessible');
is($proj_false->index, 1, 'Index is 1 for false branch');
is($proj_false->label, 'IfFalse', 'Label is IfFalse');

done_testing();
