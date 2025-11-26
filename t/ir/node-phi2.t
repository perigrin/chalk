#!/usr/bin/env perl
# ABOUTME: Tests for simplified Phi node (SSA phi function)
# ABOUTME: Selects value based on control path taken to Region
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Phi2');
use Chalk::IR::Node::Region2;
use Chalk::IR::Node::Proj2;
use Chalk::IR::Node::If2;
use Chalk::IR::Node::Start2;
use Chalk::IR::Node::Constant2;

# Build a simple if-else structure
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

my $region = Chalk::IR::Node::Region2->new(
    controls => [$proj_true, $proj_false],
);

# Create values for each branch
my $value_true = Chalk::IR::Node::Constant2->new(type => 'Int', value => 42);
my $value_false = Chalk::IR::Node::Constant2->new(type => 'Int', value => 99);

# Create Phi that selects between the two values
my $phi = Chalk::IR::Node::Phi2->new(
    region => $region,
    values => [$value_true, $value_false],
);

is($phi->id,
   'phi_region_proj_if_start_main_const_Bool_1_0_proj_if_start_main_const_Bool_1_1_const_Int_42_const_Int_99',
   'Content-addressable ID from region and all values');
is($phi->region, $region, 'Region node accessible');
is($phi->values->[0], $value_true, 'First value accessible');
is($phi->values->[1], $value_false, 'Second value accessible');
is(scalar @{$phi->values}, 2, 'Has two values');
is($phi->op, 'Phi', 'Op is Phi');

done_testing();
