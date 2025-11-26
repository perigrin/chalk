#!/usr/bin/env perl
# ABOUTME: Tests for simplified Region node (control flow merge)
# ABOUTME: Merges multiple control paths (e.g., from if-else branches)
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Region2');
use Chalk::IR::Node::Proj2;
use Chalk::IR::Node::If2;
use Chalk::IR::Node::Start2;
use Chalk::IR::Node::Constant2;

my $start = Chalk::IR::Node::Start2->new(label => 'main');
my $condition = Chalk::IR::Node::Constant2->new(type => 'Bool', value => 1);
my $if = Chalk::IR::Node::If2->new(
    control   => $start,
    condition => $condition,
);

my $proj_true = Chalk::IR::Node::Proj2->new(
    source => $if,
    index  => 0,
    label  => "IfTrue",
);

my $proj_false = Chalk::IR::Node::Proj2->new(
    source => $if,
    index  => 1,
    label  => "IfFalse",
);

# Create region that merges both branches
my $region = Chalk::IR::Node::Region2->new(
    controls => [$proj_true, $proj_false],
);

is($region->id, 'region_proj_if_start_main_const_Bool_1_0_proj_if_start_main_const_Bool_1_1',
   'Content-addressable ID from all control inputs');
is($region->controls->[0], $proj_true, 'First control input accessible');
is($region->controls->[1], $proj_false, 'Second control input accessible');
is(scalar @{$region->controls}, 2, 'Has two control inputs');
is($region->op, 'Region', 'Op is Region');

done_testing();
