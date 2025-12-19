#!/usr/bin/env perl
# ABOUTME: Tests for SignExtend and ZeroExtend IR nodes
# ABOUTME: Verifies widening from narrower to wider integer types
use 5.42.0;
use Test2::V0;
use lib 'lib';

use Chalk::IR::Node::SignExtend;
use Chalk::IR::Node::ZeroExtend;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;

subtest 'SignExtend positive value' => sub {
    # 100 (i8) sign-extended to i64 = 100
    my $const = Chalk::IR::Node::Constant->new(
        value => 100,
        type => Chalk::IR::Type::Integer->i8()
    );

    my $ext = Chalk::IR::Node::SignExtend->new(
        operand => $const,
        target_type => Chalk::IR::Type::Integer->i64()
    );

    my $result = $ext->peephole();
    ok($result->isa('Chalk::IR::Node::Constant'), 'SignExtend folds to constant');
    is($result->value, 100, 'Positive value unchanged');
};

subtest 'SignExtend negative value' => sub {
    # -56 (i8) sign-extended to i64 = -56
    my $const = Chalk::IR::Node::Constant->new(
        value => -56,
        type => Chalk::IR::Type::Integer->i8()
    );

    my $ext = Chalk::IR::Node::SignExtend->new(
        operand => $const,
        target_type => Chalk::IR::Type::Integer->i64()
    );

    my $result = $ext->peephole();
    is($result->value, -56, 'Negative value sign-extended correctly');
};

subtest 'ZeroExtend value' => sub {
    # 200 (u8) zero-extended to i64 = 200
    my $const = Chalk::IR::Node::Constant->new(
        value => 200,
        type => Chalk::IR::Type::Integer->u8()
    );

    my $ext = Chalk::IR::Node::ZeroExtend->new(
        operand => $const,
        target_type => Chalk::IR::Type::Integer->i64()
    );

    my $result = $ext->peephole();
    ok($result->isa('Chalk::IR::Node::Constant'), 'ZeroExtend folds to constant');
    is($result->value, 200, 'Value zero-extended correctly');
};

done_testing();
