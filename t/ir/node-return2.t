#!/usr/bin/env perl
# ABOUTME: Tests for simplified Return node
# ABOUTME: Control flow exit with value
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Return2');
use Chalk::IR::Node::Start2;
use Chalk::IR::Node::Store2;
use Chalk::IR::Node::Constant2;

my $start = Chalk::IR::Node::Start2->new(label => 'main');
my $value = Chalk::IR::Node::Constant2->new(type => 'Int', value => 42);
my $store = Chalk::IR::Node::Store2->new(control => $start, var => 'x', value => $value);

my $return = Chalk::IR::Node::Return2->new(
    control => $store,
    value   => $value,
);

is($return->id, 'return_store_x_start_main_const_Int_42_const_Int_42', 'Content-addressable ID');
is($return->control, $store, 'Control predecessor accessible');
is($return->value, $value, 'Value node accessible');
is($return->op, 'Return', 'Op is Return');

done_testing();
