# ABOUTME: T2's two integer-constant checks, exact on the decimal string at the word's edges: which
# ABOUTME: constants an i64 holds, and a UV constant's bits as an i64 -- IV_MIN, IV_MAX, UV_MAX and one past.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
require Chalk::IR::Analysis;
require Chalk::Target::LLVM::Builder;

# A CONSTANT IS A DECIMAL STRING from the wire ([-+]?\d+, leading zeros
# allowed). Nothing here goes through an NV: one past IV_MAX is not IV_MAX.
my $IV_MAX = '9223372036854775807';
my $IV_MIN = '-9223372036854775808';
my $UV_MAX = '18446744073709551615';

# decimal_is_iv($decimal): an i64 holds it (within [IV_MIN, IV_MAX]) -- T1's
# fact, which T2 asks before it makes an i64 constant.
my $holds = \&Chalk::IR::Analysis::decimal_is_iv;
for my $c (
    [ $IV_MAX, 1 ], [ '9223372036854775808', 0 ], [ $IV_MIN, 1 ], [ '-9223372036854775809', 0 ],
    [ $UV_MAX, 0 ], [ '18446744073709551616', 0 ], [ '-18446744073709551616', 0 ],
    [ '0', 1 ], [ '-0', 1 ], [ '+0', 1 ], [ '1', 1 ], [ '-1', 1 ],
    [ '0009223372036854775807', 1 ], [ '0009223372036854775808', 0 ], [ '-0009223372036854775808', 1 ], [ '-0009223372036854775809', 0 ],
    [ '+9223372036854775807', 1 ], [ '+9223372036854775808', 0 ],
    [ '999999999999999999', 1 ], [ '10000000000000000000', 0 ], [ '-999999999999999999', 1 ], [ '-10000000000000000000', 0 ],
    [ '9999999999999999999', 0 ], [ '-9999999999999999999', 0 ], [ '1000000000000000000000000', 0 ],
) {
    my ( $d, $want ) = @$c;
    is( $holds->($d) ? 1 : 0, $want, "decimal_is_iv($d): " . ( $want ? 'yes' : 'no' ) );
}

# uv_bits($decimal): a constant past IV_MAX and within UV_MAX -- a UV perl
# folded -- as the signed i64 of its bits; undef for any other.
my $bits = \&Chalk::Target::LLVM::Builder::uv_bits;
for my $c (
    [ $IV_MAX, undef ], [ '9223372036854775808', '-9223372036854775808' ], [ '9223372036854775809', '-9223372036854775807' ],
    [ $UV_MAX, '-1' ], [ '18446744073709551614', '-2' ], [ '18446744073709551610', '-6' ], [ '18446744073709551616', undef ],
    [ '0009223372036854775808', '-9223372036854775808' ], [ '+18446744073709551615', '-1' ], [ '00018446744073709551615', '-1' ],
    [ '00018446744073709551616', undef ], [ '-9223372036854775809', undef ], [ '-1', undef ], [ '-0', undef ], [ '0', undef ],
    [ '99999999999999999999', undef ], [ '100000000000000000000', undef ], [ '1.5', undef ], [ 'abc', undef ],
) {
    my ( $d, $want ) = @$c;
    is( $bits->($d), $want, "uv_bits($d): " . ( $want // 'undef' ) );
}

done_testing;
