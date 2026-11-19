# ABOUTME: T2's scalar has perl's three numeric forms: IV, UV (past IV_MAX) and NV. Each
# ABOUTME: numeric reader answers as perl at IV_MAX, IV_MIN and UV_MAX, never wrapping or stopping.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
use Chalk::CodeGen::Harness::LLI;
Chalk::CodeGen::Harness::LLI->lli;
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

# PERL HAS THREE NUMERIC FORMS (sv.h): an IV, a UV -- an integer past IV_MAX,
# up to UV_MAX -- and an NV. pp_add, pp_subtract and pp_multiply keep two
# integers an integer while the exact result fits an IV or a UV, else the
# operands' numbers' NV. T2's %Slot held no UV: a result perl makes one wrapped
# (4611686018427387904 * 2 printed -9223372036854775808), then stopped by name.
# Each program below is run by perl and by T2, and must print the same.
my %prog;

# + - * at the edges, on what T2 holds in a %Slot (`$ENV{..} //`): an IV
# while one fits, a UV past IV_MAX, an NV past UV_MAX or below IV_MIN -- and
# back down to an IV. (On what T1 types Int: t2-integer-intervals.t.)
{
    my $IVMAX = '9223372036854775807';
    my $IVMIN = '(-9223372036854775807 - 1)';
    my @e = ( [ $IVMAX, '$x + 1' ], [ $IVMAX, '$x + $x' ], [ $IVMAX, '$x + $x + 1' ], [ $IVMAX, '$x + $x + 2' ],
        [ $IVMAX, '$x - -1' ], [ $IVMIN, '1 - $x' ], [ $IVMIN, '0 - $x' ], [ $IVMIN, '$x * -1' ], [ $IVMIN, '-$x' ],
        [ '4611686018427387904', '$x * 2' ], [ '4611686018427387904', '$x * 4' ], [ '-4611686018427387904', '$x * -2' ],
        [ '3037000500', '$x * $x' ], [ '4294967296', '$x * $x' ], [ '4294967295', '$x * $x' ],
        [ '-9223372036854775807', '$x - 2' ], [ $IVMAX, '$x * -1 - 2' ], [ $IVMAX, '($x + 1) - 1' ], [ $IVMAX, '($x + 1) - $x' ],
        [ $IVMAX, '($x + 1) * 2' ], [ $IVMAX, '($x + $x + 1) + 1' ], [ $IVMAX, '($x + $x + 1) - ($x + 1)' ], [ $IVMAX, '0 - ($x + 1)' ],
        [ $IVMAX, '0 - ($x + 2)' ], [ $IVMAX, '-($x + 1)' ], [ $IVMAX, '-($x + 2)' ], [ $IVMAX, '($x + 1) * 0' ], [ $IVMAX, '($x + 1) * -1' ],
        [ $IVMIN, '($x - 1)' ], [ $IVMIN, '$x + ($x * -1)' ], [ $IVMAX, '($x + 1) + $x * -1' ], [ $IVMIN, '(0 - $x) + $x' ],
    );
    for my $k ( [ slot => sub ($v) { "my \$x = \$ENV{CHALK_NO_SUCH} // $v;" } ] ) {
        my ( $kind, $mk ) = @$k;
        $prog{"+ - * at the edges ($kind)"} = join '', map {
            my ( $v, $e ) = @$_;
            "{ " . $mk->($v) . " my \$r = $e; print '$e: ', \$r, \"\\n\"; }\n"
        } @e;
    }
}

# ++ AND -- ACROSS IV_MAX AND UV_MAX (sv_inc, sv_dec): IV_MAX ++ is a UV, a
# UV_MAX ++ the NV 2**64; IV_MIN -- an NV; a digit string's ++ is perl's magic one.
$prog{'p-step'} = <<'PL';
my $u = $ENV{CHALK_NO_SUCH} // 9223372036854775806; $u++; print "$u "; $u++; print "$u "; $u++; print "$u "; $u--; print "$u "; $u--; print "$u\n";
my $m = $ENV{CHALK_NO_SUCH} // "18446744073709551614"; $m++; print "$m "; $m++; print "$m "; $m--; print "$m\n";
my $v = 0 + ($ENV{CHALK_NO_SUCH} // "18446744073709551614"); $v++; print "$v "; $v++; print "$v "; $v--; print "$v\n";
my $n = $ENV{CHALK_NO_SUCH} // (-9223372036854775807 - 1); $n--; print "$n "; $n++; print "$n\n";
my $f = $ENV{CHALK_NO_SUCH} // 1e15; $f++; print "$f "; my $g = $ENV{CHALK_NO_SUCH} // 1e17; $g++; print "$g\n";
PL

# ** OF INTEGERS (pp_pow): an integer while its bits times the power fit 64 --
# a UV past IV_MAX -- a power of 2 and anything larger pow()'s NV.
$prog{'p-pow'} = <<'PL';
my $b = $ENV{CHALK_NO_SUCH} // 255; my $nb = 0 - $b; my $t = $ENV{CHALK_NO_SUCH} // 2; my $f = $ENV{CHALK_NO_SUCH} // 15;
print $b ** 8, " ", $nb ** 8, " ", $nb ** 7, " ", $f ** 16, " ", $t ** 63, " ", (0 - $t) ** 63, " ", 3 ** 40, " ", $t ** 64, " ", $b ** 0, "\n";
my $u = ($ENV{CHALK_NO_SUCH} // 9223372036854775807) + 2; print $u ** 1, " ", $u ** 2, "\n";
PL

# UNARY MINUS, abs AND int of each form (pp_negate, pp_abs, pp_int): -IV_MIN and abs(IV_MIN) are UVs, int keeps an IV or a UV whole
$prog{'p-neg'} = <<'PL';
my $i = $ENV{CHALK_NO_SUCH} // 9223372036854775807;
my $u = $i + 1; my $v = $i + $i + 1; my $min = -$i - 1;
print -$u, " ", -$v, " ", -$min, " ", -($u - 1), "\n";
print abs($min), " ", abs($u), " ", abs(-$v), " ", abs(-5), " ", abs(-2.5), " ", abs($i * -1), " ", abs("-7"), "\n";
print int($u), " ", int($v), " ", int($min), " ", int(1e15), " ", int(-1e15), " ", int(1e20), " ", int(-2.5), " ", int(2**63), " ", int(1.8e19), " ", int(-9.3e18), "\n";
PL

# COMPARISONS between IV, UV and NV, as perl's (do_ncmp): two integers exactly, past 2**53 too; else as numbers
$prog{'p-cmp'} = <<'PL';
my $i = $ENV{CHALK_NO_SUCH} // 9223372036854775807;
my $j = $i - 1; my $u = $i + 1; my $v = $i + $i + 1; my $min = -$i - 1; my $big = 2 ** 64; my $t = 2 ** 63;
my @v = ($i, $j, $u, $v, $min, $big, $t, 9007199254740993, 9007199254740992.0, -1, 0, 1.5);
my $o = "";
for my $a (@v) { for my $b (@v) { $o .= ($a <=> $b) + 1; $o .= $a == $b ? "e" : $a < $b ? "l" : "g"; $o .= ($a != $b ? 1 : 0) . ($a >= $b ? 1 : 0) . ($a <= $b ? 1 : 0) . ($a > $b ? 1 : 0) } $o .= "\n" }
print $o;
print join(",", sort { $a <=> $b } $u, $i, $v, $min, $j, $t, -1), "\n";
PL

# / AND % (pp_divide, pp_modulo): an exact quotient past 2**53 an integer, % on UVs; an NV that is a whole number below 2**53 is an integer to + - * (1e15 * 10 prints whole)
$prog{'p-divmod'} = <<'PL';
my $i = $ENV{CHALK_NO_SUCH} // 9223372036854775807;
my $v = $i + $i + 1; my $u = $i + 1; my $min = -$i - 1;
print $i / 1, " ", $v / 5, " ", $v / 3, " ", $u / 2, " ", $u / -2, " ", $min / -1, " ", $min / 2, " ", $v / $v, " ", 7 / 2, " ", $i / 7, "\n";
print $v % 10, " ", -7 % $v, " ", $min % -1, " ", $v % -3, " ", $u % 3, " ", $min % 3, " ", 7 % -3, " ", -7 % 3, " ", $i % $u, " ", 1e20 % 7, "\n";
my $x = $ENV{CHALK_NO_SUCH} // 1e15; print $x * 10, " ", $x + 1, " ", $x - 1, " ", $x * $x, " ", $x / 4, "\n";
my $y = $ENV{CHALK_NO_SUCH} // 9007199254740992; print $y + 1, " ", $y * 2, " ", ($y / 2) * 2 + 1, "\n";
PL

# BITWISE OPS ARE ON UVs (pp_bit_and & co., no use integer): ~0 is UV_MAX, 1 << 63 a UV
$prog{"p-bit"} = <<'PL';
my $z = 0; my $one = 1; my $m1 = -1;
print ~$z, " ", $one << 63, " ", $one << 64, " ", $m1 >> 1, " ", $m1 & 255, " ", (~$z) >> 1, " ", ($one << 63) | 1, " ", ~$one, " ", (~$z) ^ 1, " ", $m1 | 0, "\n";
my $u = ($one << 63) + 5; print $u & 7, " ", $u >> 60, " ", $u ^ 255, " ", $u + 1, "\n";
PL

# sprintf %d %u %s %x %o %e OF EACH FORM: %d of a UV past IV_MAX wraps as perl's, %u of -1 is UV_MAX
$prog{'p-fmt'} = <<'PL';
my $i = $ENV{CHALK_NO_SUCH} // 9223372036854775807;
my $u = $i + 1; my $v = $i + $i + 1; my $min = -$i - 1; my $m1 = $ENV{CHALK_NO_SUCH} // -1;
print sprintf("%d %u %s %x %o|", $u, $u, $u, $u, $u), sprintf("%d %u %s %x|", $v, $v, $v, $v), sprintf("%d %u %s %x|", $min, $min, $min, $min),
  sprintf("%d %u %x|", $m1, $m1, $m1), sprintf("%d %d %u|", 1e20, -1e20, 1e20), sprintf("%5d|%-22u|%e", 42, $u, $u), "\n";
PL

# hex AND oct PAST IV_MAX are UVs
$prog{'p-hex'} = <<'PL';
my @h = map { $ENV{CHALK_NO_SUCH} // $_ } ("FFFFFFFFFFFFFFFF", "8000000000000000", "7fffffffffffffff", "ff", "0x1F");
print join(" ", map { hex($_) } @h), "\n";
my @o = map { $ENV{CHALK_NO_SUCH} // $_ } ("0xFFFFFFFFFFFFFFFF", "01777777777777777777777", "0b1111111111111111111111111111111111111111111111111111111111111111", "777", "0x8000000000000000", "1000000000000000000000");
print join(" ", map { oct($_) } @o), "\n";
my $h = hex($h[0]); print $h + 0, " ", $h - 1, " ", $h + 1, " ", $h == 18446744073709551615 ? "eq" : "ne", "\n";
PL

# A STRING'S NUMBER past IV_MAX (grok_number): a UV within UV_MAX, an NV past it
$prog{'p-str'} = <<'PL';
my @s = map { $ENV{CHALK_NO_SUCH} // $_ } ("18446744073709551615", "9223372036854775808", "18446744073709551616", "-9223372036854775809", " 9223372036854775808 ", "9223372036854775807", "-9223372036854775808", "99999999999999999999", "1e15", "1.5e15", "0x10");
print join(" ", map { $_ + 0 } @s), "\n";
print join(" ", map { $_ + 1 } @s), "\n";
print join(" ", map { $_ * 1 } @s), "\n";
print join(" ", map { $_ - 1 } @s), "\n";
PL

# A UV PERL FOLDED (`9223372036854775807 + 1` is a constant) is a UV constant
$prog{'p-const'} = <<'PL';
print 9223372036854775807 + 1, " ", 4611686018427387904 * 2, " ", 18446744073709551615, " ", 18446744073709551615 + 0, " ", 9223372036854775808 - 1, " ", -9223372036854775808, "\n";
my $c = 18446744073709551615; my $d = 9223372036854775808; print $c, " ", $d, " ", $c - $d, " ", $c + 1, " ", $d * 2, " ", -$d, "\n";
PL

# EVERY READER THAT SWITCHES ON A NUMBER'S FORM HAS AN ARM FOR THE UV (tag
# 4): one without it takes its default arm -- undef, a wrong value, not an
# error (docs/plans/2026-08-31-t2-is-a-narrowing-analysis.md).
{
    require Chalk::Target::LLVM::Runtime;
    my $rt = Chalk::Target::LLVM::Runtime::prelude();
    for my $f (qw(t2_slot_numify t2_slot_num t2_slot_str t2_truth_slot t2_arith_num)) {
        my ($body) = $rt =~ /^define [^\n]*\@\Q$f\E\(.*?^\}/msp ? ${^MATCH} : ('');
        my ($sw) = $body =~ /(switch i8 %t, label %\w+ \[.*?\])/s;
        like $sw // '', qr/\bi8 4, label/, "$f has an arm for a UV";
    }
}

for my $name ( sort keys %prog ) {
    my $r = tap( $prog{$name} );
    # (p-divmod's `-7 % $v` is on no control chain, with prints before it: the
    # loader refuses it by name, as it would the same wire dying late.)
    if ( $r->{verdict} eq 'REFUSED' && ( $r->{why} // '' ) =~ /GAP: a (?:division|modulus) whose divisor may be zero, on no control chain/ ) {
        pass "$name: refused by name";
        next;
    }
    is $r->{verdict}, 'SAME', "$name: as perl" or diag $r->{why} // '', "\n", explain $r;
}

# WHERE PERL WARNS OF A hex OR AN oct -- past UV_MAX always; under warnings a
# value past 32 bits (non-portable) or a character that is no digit -- T2
# raises no warning: stopped by name, not answered without it. Within them,
# as perl.
{
    my $r = tap(qq{use warnings; my \$h = \$ENV{CHALK_NO_SUCH} // "ff"; print hex(\$h), " ", oct("0" . \$h), "\\n";\n});
    is $r->{verdict}, 'SAME', 'hex under warnings, within 32 bits: as perl' or diag explain $r;
    for my $c ( [ 'use warnings; ', 'FFFFFFFFF' ], [ 'use warnings; ', 'fg' ], [ '', '1FFFFFFFFFFFFFFFF' ] ) {
        my ( $w, $v ) = @$c;
        $r = tap(qq{$w my \$h = \$ENV{CHALK_NO_SUCH} // "$v"; print hex(\$h), "\\n";\n});
        is $r->{llvm}{exit}, 255, "hex('$v')" . ( $w ? ' under warnings' : '' ) . ': stopped' or diag explain $r;
        like $r->{llvm}{err} // '', qr/hex or oct .*stopped/, '  naming why';
    }
}

done_testing;
