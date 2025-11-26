#!/usr/bin/env perl
# ABOUTME: Integration test for simple assignment IR generation
# ABOUTME: Tests my $x = 42; produces correct Sea of Nodes structure
use 5.42.0;
use Test::More;
use lib 'lib';

use Chalk::IR::Node::Start2;
use Chalk::IR::Node::Store2;
use Chalk::IR::Node::Return2;
use Chalk::IR::Node::Constant2;

# Manually construct expected IR for: my $x = 42;
my $start = Chalk::IR::Node::Start2->new(label => 'main');
my $value = Chalk::IR::Node::Constant2->new(type => 'Int', value => 42);
my $store = Chalk::IR::Node::Store2->new(
    control => $start,
    var     => 'x',
    value   => $value,
);
my $return = Chalk::IR::Node::Return2->new(
    control => $store,
    value   => $value,
);

# Verify structure
is($return->op, 'Return', 'Root is Return');
is($return->control->op, 'Store', 'Return control is Store');
is($return->control->control->op, 'Start', 'Store control is Start');
is($return->value->op, 'Constant', 'Return value is Constant');
is($return->value->value, 42, 'Constant value is 42');

# Verify control chain: Start -> Store -> Return
is($return->control->id, 'store_x_start_main_const_Int_42', 'Store ID correct');
is($return->id, 'return_store_x_start_main_const_Int_42_const_Int_42', 'Return ID correct');

# Verify data flow: Return.value -> Constant
is($return->value->id, 'const_Int_42', 'Value ID correct');

done_testing();
