#!/usr/bin/env perl
# ABOUTME: Tests for Integer2 rule semantic action
# ABOUTME: Validates Constant node creation from integer literal
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::Grammar::Chalk::Rule::Integer2');
use Chalk::IR::Node::Constant2;

# Mock context that returns '42' as the matched text
{
    package MockContext;
    sub new { bless { text => $_[1] }, $_[0] }
    sub child { return $_[0]->{text} }
    sub env { return {} }
}

my $ctx = MockContext->new('42');
my $rule = Chalk::Grammar::Chalk::Rule::Integer2->new();
my $result = $rule->evaluate($ctx);

isa_ok($result, 'Chalk::IR::Node::Constant2');
is($result->type, 'Int', 'Type is Int');
is($result->value, 42, 'Value is 42');
is($result->id, 'const_Int_42', 'ID is content-addressable');

done_testing();
