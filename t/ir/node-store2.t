#!/usr/bin/env perl
# ABOUTME: Tests for simplified Store node
# ABOUTME: Control node for variable assignment
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Store2');
use Chalk::IR::Node::Start2;
use Chalk::IR::Node::Constant2;

my $start = Chalk::IR::Node::Start2->new(label => 'main');
my $value = Chalk::IR::Node::Constant2->new(type => 'Int', value => 42);

my $store = Chalk::IR::Node::Store2->new(
    control => $start,
    var     => 'x',
    value   => $value,
);

is($store->id, 'store_x_start_main_const_Int_42', 'Content-addressable ID');
is($store->var, 'x', 'Variable name accessible');
is($store->control, $start, 'Control predecessor accessible');
is($store->value, $value, 'Value node accessible');
is($store->op, 'Store', 'Op is Store');

done_testing();
