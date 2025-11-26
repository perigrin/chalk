#!/usr/bin/env perl
# ABOUTME: Tests for simplified Negate node
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Negate2');
use Chalk::IR::Node::Constant2;

my $operand = Chalk::IR::Node::Constant2->new(type => 'Int', value => 42);

my $negate = Chalk::IR::Node::Negate2->new(operand => $operand);

is($negate->id, 'negate_const_Int_42', 'Content-addressable ID');
is($negate->operand, $operand, 'Operand accessible');
is($negate->op, 'Negate', 'Op is Negate');

my $hash = $negate->to_hash;
is($hash->{id}, 'negate_const_Int_42', 'to_hash: correct ID');
is($hash->{op}, 'Negate', 'to_hash: correct op');
is_deeply($hash->{inputs}, ['const_Int_42'], 'to_hash: correct inputs');
is($hash->{attributes}{operand}, 'const_Int_42', 'to_hash: correct operand attribute');

done_testing();
