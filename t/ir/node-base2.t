#!/usr/bin/env perl
# ABOUTME: Tests for simplified IR::Node::Base2
# ABOUTME: Validates basic node structure and ID generation
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Base2');

# Test that Base2 can be subclassed
{
    package TestNode;
    use 5.42.0;
    use experimental 'class';
    class TestNode :isa(Chalk::IR::Node::Base2) {
        field $value :param :reader;
        field $id :reader = "test_${value}";
    }
}

my $node = TestNode->new(value => 42);
is($node->id, 'test_42', 'ID computed from field');
is($node->value, 42, 'Value accessible');
ok($node->inputs, 'inputs method exists');

done_testing();
