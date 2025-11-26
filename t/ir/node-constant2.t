#!/usr/bin/env perl
# ABOUTME: Tests for simplified Constant node
# ABOUTME: Validates content-addressable ID generation
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Constant2');

my $c1 = Chalk::IR::Node::Constant2->new(type => 'Int', value => 42);
is($c1->id, 'const_Int_42', 'Content-addressable ID');
is($c1->type, 'Int', 'Type accessible');
is($c1->value, 42, 'Value accessible');
is($c1->op, 'Constant', 'Op is Constant');

# Same inputs = same ID (content-addressable)
my $c2 = Chalk::IR::Node::Constant2->new(type => 'Int', value => 42);
is($c2->id, $c1->id, 'Same inputs produce same ID');

# Different inputs = different ID
my $c3 = Chalk::IR::Node::Constant2->new(type => 'Int', value => 99);
isnt($c3->id, $c1->id, 'Different inputs produce different ID');

done_testing();
