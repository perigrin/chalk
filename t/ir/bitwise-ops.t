#!/usr/bin/env perl
# ABOUTME: Tests for bitwise operation IR nodes
# ABOUTME: Verifies BitAnd, BitOr, BitXor, BitNot with peephole optimizations
use 5.42.0;
use Test2::V0;
use lib 'lib';

use Chalk::IR::Node::BitAnd;
use Chalk::IR::Node::BitOr;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;

subtest 'BitAnd constant folding' => sub {
    my $a = Chalk::IR::Node::Constant->new(value => 0b11110000, type => Chalk::IR::Type::Integer->i64());
    my $b = Chalk::IR::Node::Constant->new(value => 0b10101010, type => Chalk::IR::Type::Integer->i64());

    my $and = Chalk::IR::Node::BitAnd->new(left => $a, right => $b);
    my $result = $and->peephole();

    ok($result->isa('Chalk::IR::Node::Constant'), 'BitAnd folds to constant');
    is($result->value, 0b10100000, 'BitAnd computed correctly');
};

subtest 'BitAnd identity x & -1 = x' => sub {
    my $x = Chalk::IR::Node::Constant->new(value => 42, type => Chalk::IR::Type::Integer->i64());
    my $neg1 = Chalk::IR::Node::Constant->new(value => -1, type => Chalk::IR::Type::Integer->i64());

    my $and = Chalk::IR::Node::BitAnd->new(left => $x, right => $neg1);
    my $result = $and->peephole();

    is($result->value, 42, 'x & -1 = x');
};

subtest 'BitAnd annihilator x & 0 = 0' => sub {
    my $x = Chalk::IR::Node::Constant->new(value => 42, type => Chalk::IR::Type::Integer->i64());
    my $zero = Chalk::IR::Node::Constant->new(value => 0, type => Chalk::IR::Type::Integer->i64());

    my $and = Chalk::IR::Node::BitAnd->new(left => $x, right => $zero);
    my $result = $and->peephole();

    is($result->value, 0, 'x & 0 = 0');
};

subtest 'BitOr constant folding' => sub {
    my $a = Chalk::IR::Node::Constant->new(value => 0b11110000, type => Chalk::IR::Type::Integer->i64());
    my $b = Chalk::IR::Node::Constant->new(value => 0b00001111, type => Chalk::IR::Type::Integer->i64());

    my $or = Chalk::IR::Node::BitOr->new(left => $a, right => $b);
    my $result = $or->peephole();

    ok($result->isa('Chalk::IR::Node::Constant'), 'BitOr folds to constant');
    is($result->value, 0b11111111, 'BitOr computed correctly');
};

subtest 'BitOr identity x | 0 = x' => sub {
    my $x = Chalk::IR::Node::Constant->new(value => 42, type => Chalk::IR::Type::Integer->i64());
    my $zero = Chalk::IR::Node::Constant->new(value => 0, type => Chalk::IR::Type::Integer->i64());

    my $or = Chalk::IR::Node::BitOr->new(left => $x, right => $zero);
    my $result = $or->peephole();

    is($result->value, 42, 'x | 0 = x');
};

done_testing();
