#!/usr/bin/env perl
# ABOUTME: Test Token class stringification and comparison operators
use 5.42.0;
use experimental qw(class);
use Test2::V0;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Chalk::Grammar::Token;

# Test stringification
my $token = Chalk::Grammar::Token->new(value => 'test', pattern_name => 'IDENTIFIER');
is("$token", 'test', 'Token stringifies to its value');

# Test eq operator
my $token2 = Chalk::Grammar::Token->new(value => 'test', pattern_name => 'IDENTIFIER');
ok($token eq $token2, 'Token eq Token with same value');
ok($token eq 'test', 'Token eq string');
ok('test' eq $token, 'string eq Token');

# Test ne operator
my $token3 = Chalk::Grammar::Token->new(value => 'other', pattern_name => 'IDENTIFIER');
ok($token ne $token3, 'Token ne Token with different value');
ok($token ne 'other', 'Token ne string');
ok('other' ne $token, 'string ne Token');

# Test cmp operator
my $token_a = Chalk::Grammar::Token->new(value => 'a', pattern_name => 'IDENTIFIER');
my $token_b = Chalk::Grammar::Token->new(value => 'b', pattern_name => 'IDENTIFIER');
ok(($token_a cmp $token_b) < 0, 'Token a cmp Token b');
ok(($token_b cmp $token_a) > 0, 'Token b cmp Token a');
ok(($token_a cmp $token_a) == 0, 'Token a cmp Token a');

# Test is_operator
ok(!$token->is_operator, 'Regular Token is not an operator');

# Test Operator subclass
my $op_token = Chalk::Grammar::Token::Operator->new(value => '+', pattern_name => 'ARITHMETIC_OP');
ok($op_token->is_operator, 'Operator Token is an operator');
is("$op_token", '+', 'Operator Token stringifies correctly');

done_testing;
