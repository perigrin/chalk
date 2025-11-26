#!/usr/bin/env perl
# ABOUTME: Tests for simplified Not node
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Not2');
use Chalk::IR::Node::Constant2;

my $operand = Chalk::IR::Node::Constant2->new(type => 'Bool', value => 1);

my $not = Chalk::IR::Node::Not2->new(operand => $operand);

is($not->id, 'not_const_Bool_1', 'Content-addressable ID');
is($not->operand, $operand, 'Operand accessible');
is($not->op, 'Not', 'Op is Not');

my $hash = $not->to_hash;
is($hash->{id}, 'not_const_Bool_1', 'to_hash: correct ID');
is($hash->{op}, 'Not', 'to_hash: correct op');
is_deeply($hash->{inputs}, ['const_Bool_1'], 'to_hash: correct inputs');
is($hash->{attributes}{operand}, 'const_Bool_1', 'to_hash: correct operand attribute');

done_testing();
