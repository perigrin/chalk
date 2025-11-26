#!/usr/bin/env perl
# ABOUTME: Tests for simplified Start node
# ABOUTME: Entry point for control flow
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Start2');

my $start = Chalk::IR::Node::Start2->new(label => 'main');
is($start->id, 'start_main', 'Content-addressable ID');
is($start->label, 'main', 'Label accessible');
is($start->op, 'Start', 'Op is Start');

done_testing();
