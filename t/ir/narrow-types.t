#!/usr/bin/env perl
# ABOUTME: Tests for narrow integer types (i8, i16, i32, u8, u16, u32)
# ABOUTME: Verifies bits/signed parameters and range calculations
use 5.42.0;
use Test2::V0;
use lib 'lib';

use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;

subtest 'Integer type constructors' => sub {
    my $i8 = Chalk::IR::Type::Integer->i8();
    is($i8->bits, 8, 'i8 has 8 bits');
    is($i8->signed, 1, 'i8 is signed');

    my $u32 = Chalk::IR::Type::Integer->u32();
    is($u32->bits, 32, 'u32 has 32 bits');
    is($u32->signed, 0, 'u32 is unsigned');
};

subtest 'Integer range calculations' => sub {
    my $i8 = Chalk::IR::Type::Integer->i8();
    is($i8->min, -128, 'i8 min is -128');
    is($i8->max, 127, 'i8 max is 127');

    my $u8 = Chalk::IR::Type::Integer->u8();
    is($u8->min, 0, 'u8 min is 0');
    is($u8->max, 255, 'u8 max is 255');
};

subtest 'Integer mask calculation' => sub {
    my $i8 = Chalk::IR::Type::Integer->i8();
    is($i8->mask, 0xFF, 'i8 mask is 0xFF');

    my $u16 = Chalk::IR::Type::Integer->u16();
    is($u16->mask, 0xFFFF, 'u16 mask is 0xFFFF');
};

subtest 'Float type constructors' => sub {
    my $f32 = Chalk::IR::Type::Float->f32();
    is($f32->bits, 32, 'f32 has 32 bits');

    my $f64 = Chalk::IR::Type::Float->f64();
    is($f64->bits, 64, 'f64 has 64 bits');
};

done_testing();
