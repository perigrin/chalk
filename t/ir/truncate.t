#!/usr/bin/env perl
# ABOUTME: Tests for Truncate IR node
# ABOUTME: Verifies narrowing from wider to narrower integer types
use 5.42.0;
use Test2::V0;
use lib 'lib';

use Chalk::IR::Node::Truncate;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;

subtest 'Truncate constant folding' => sub {
    # 300 truncated to i8 = 44 (300 & 0xFF = 44)
    my $const = Chalk::IR::Node::Constant->new(
        value => 300,
        type => Chalk::IR::Type::Integer->i64()
    );

    my $trunc = Chalk::IR::Node::Truncate->new(
        operand => $const,
        target_type => Chalk::IR::Type::Integer->i8()
    );

    my $result = $trunc->peephole();
    ok($result->isa('Chalk::IR::Node::Constant'), 'Truncate folds to constant');
    is($result->value, 44, 'Truncated value is 44');
};

subtest 'Truncate signed wraparound' => sub {
    # 200 truncated to i8 = -56 (200 & 0xFF = 200, sign extend = -56)
    my $const = Chalk::IR::Node::Constant->new(
        value => 200,
        type => Chalk::IR::Type::Integer->i64()
    );

    my $trunc = Chalk::IR::Node::Truncate->new(
        operand => $const,
        target_type => Chalk::IR::Type::Integer->i8()
    );

    my $result = $trunc->peephole();
    is($result->value, -56, 'Signed truncation wraps correctly');
};

done_testing();
