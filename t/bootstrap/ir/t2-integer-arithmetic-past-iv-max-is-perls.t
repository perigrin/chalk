# ABOUTME: + - * ++ -- and unary minus on integers through T2 answer as perl at IV_MAX and IV_MIN:
# ABOUTME: an IV while one fits, a UV past IV_MAX, perl's number past UV_MAX; the fallback refuses by name.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

# PERL'S RULE (pp_add, pp_subtract, pp_multiply): two integers give an integer
# while the exact result fits an IV or a UV, else the number of the operands'
# numbers. A UV is past IV_MAX: T2's %Slot holds one (tag 4), and an Int
# + - * is an i64 op only where T1's intervals prove an IV -- it was printed
# wrapped: 4611686018427387904 * 2 said -9223372036854775808.
my $IVMAX = '9223372036854775807';
my $IVMIN = '(-9223372036854775807 - 1)';

# Operands T2 types Int (an i64) and operands it keeps in a %Slot (`$ENV{..} //`).
my %in = (
    int  => sub ($v) { "my \$x = $v;" },
    slot => sub ($v) { "my \$x = \$ENV{CHALK_NO_SUCH} // $v;" },
);

# Results that fit an IV, and results past UV_MAX or below IV_MIN (perl's
# number): the same as perl, either kind.
my @same_both = (
    [ $IVMAX, '$x + 0' ], [ $IVMAX, '$x - 1' ], [ '-9223372036854775807', '$x - 1' ],
    [ '3037000499', '$x * $x' ], [ '-4611686018427387904', '$x * 2' ], [ $IVMIN, '$x * 0' ],
    [ $IVMAX, '-$x' ], [ '-4611686018427387904', '$x + $x' ], [ $IVMIN, '$x + 1' ],
);
my @same_slot = (
    [ '-9223372036854775807', '$x - 2' ], [ $IVMIN, '$x - 1' ], [ '4611686018427387904', '$x * 4' ],
    [ '-3037000500', '$x * 3037000500' ], [ '-9223372036854775807', '$x + $x' ], [ $IVMAX, '$x * -1 - 2' ],
);
for my $kind (sort keys %in) {
    for my $c ( @same_both, @same_slot ) {
        my ($v, $e) = @$c;
        my $r = tap( $in{$kind}->($v) . " my \$r = $e; print \"\$r\\n\";\n" );
        is $r->{verdict}, 'SAME', "$kind: $e over $v as perl" or diag $r->{why} // explain $r;
    }
}

# A UV: perl's, both kinds.
my @uv = (
    [ $IVMAX, '$x + 1' ], [ $IVMAX, '$x + $x' ], [ $IVMAX, '$x - -1' ], [ $IVMIN, '1 - $x' ],
    [ '4611686018427387904', '$x * 2' ], [ '-4611686018427387904', '$x * -2' ], [ '3037000500', '$x * $x' ],
    [ $IVMIN, '-$x' ], [ $IVMIN, '0 - $x' ], [ $IVMIN, '$x * -1' ],
);
for my $kind (sort keys %in) {
    for my $c (@uv) {
        my ($v, $e) = @$c;
        my $r = tap( $in{$kind}->($v) . " my \$r = $e; print \"\$r\\n\";\n" );
        is $r->{verdict}, 'SAME', "$kind: $e over $v: a UV, as perl" or diag $r->{why} // explain $r;
    }
}

# ++ AND --: IV_MAX + 1 is a UV, IV_MIN - 1 perl's number.
{
    my $r = tap("my \$x = \$ENV{CHALK_NO_SUCH} // $IVMIN; \$x--; print \"\$x\\n\";\n");
    is $r->{verdict}, 'SAME', '-- past IV_MIN: perl\'s number' or diag $r->{why} // explain $r;
    $r = tap("my \$x = \$ENV{CHALK_NO_SUCH} // $IVMAX; \$x++; print \"\$x\\n\";\n");
    is $r->{verdict}, 'SAME', '++ past IV_MAX: a UV, as perl' or diag $r->{why} // explain $r;
    $r = tap("my \$x = \$ENV{CHALK_NO_SUCH} // 9223372036854775806; \$x++; print \"\$x\\n\";\n");
    is $r->{verdict}, 'SAME', '++ to IV_MAX: as perl' or diag $r->{why} // explain $r;
    $r = tap("my \$p = 1; \$p *= 2 for 1 .. 62; print \"\$p\\n\";\n");
    is $r->{verdict}, 'SAME', 'doubling to 2**62' or diag $r->{why} // explain $r;
    $r = tap("my \$p = 1; \$p *= 2 for 1 .. 63; print \"\$p\\n\";\n");
    is $r->{verdict}, 'SAME', 'doubling to 2**63, a UV: as perl' or diag $r->{why} // explain $r;
}

# A UV PERL FOLDED (`9223372036854775807 + 1` is a constant) is a UV constant in T2.
{
    my $r = tap("print 9223372036854775807 + 1, \"\\n\";\n");
    is $r->{verdict}, 'SAME', 'a UV constant: as perl' or diag $r->{why} // explain $r;
}

# A STRING'S INTEGER at the edges is perl's: IV_MAX and IV_MIN whole (they went
# through a double, 9.22337203685478e+18), one past IV_MIN a number, one past
# IV_MAX a UV.
for my $c ( [ '"9223372036854775807"', '$x + 0', 'SAME' ], [ '"9223372036854775807"', '$x - 7', 'SAME' ],
            [ '"-9223372036854775808"', '$x + 0', 'SAME' ], [ '"-9223372036854775809"', '$x + 0', 'SAME' ],
            [ '"99999999999999999999"', '$x + 0', 'SAME' ], [ '"9223372036854775807"', '$x + 1', 255 ],
            [ '"9223372036854775808"', '$x + 0', 255 ] ) {
    my ($v, $e, $want) = @$c;
    my $r = tap("my \$x = \$ENV{CHALK_NO_SUCH} // $v; my \$r = $e; print \"\$r\\n\";\n");
    if ($want eq 'SAME') { is $r->{verdict}, 'SAME', "the string $v: $e as perl" or diag $r->{why} // explain $r }
    else                 { is $r->{verdict}, 'SAME', "the string $v: $e, a UV: as perl" or diag $r->{why} // explain $r }
}

# THE FALLBACK (Context) IS HELD TO THE SAME: it emitted a wrapping i64 add.
# Where both operands are literals it refuses while lowering; else the program
# stops where the exact result leaves an i64.
{
    require Chalk::CodeGen::Pipeline;
    require Chalk::Target::LLVM::Lower;
    no warnings 'redefine', 'once';
    local *Chalk::Target::LLVM::Lower::lower_program = sub {
        $Chalk::Target::LLVM::Lower::PATH = { path => 'fallback', why => 'forced by the test' };
        return undef;
    };
    my $fallback = sub ($src) {
        my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
        print $fh $src; close $fh;
        my $json = qx($^X -I$SON -MO=-q,SoN,json,not_package=SoN $pl 2>/dev/null);
        my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
        my ($units, undef, undef, $err) = eval { Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1) };
        $err //= $@ if $@;
        my $u = ( $units // [] )->[0];
        return { why => $err // $u->{err} } unless !$err && $u && $u->{ok};
        my ( $lf, $ll ) = tempfile( SUFFIX => '.ll', UNLINK => 1 );
        print $lf $u->{ll}; close $lf;
        my $lli = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
        my $out = qx($lli $ll 2>&1);
        return { out => $out, exit => $? >> 8, perl => scalar qx($^X $pl) };
    };
    my $n = 'my $n = length($ENV{CHALK_NO_SUCH} // "abcd");';
    my $r = $fallback->("$n my \$r = \$n * 2305843009213693951; print \"\$r\\n\";\n");
    is $r->{out}, $r->{perl}, 'the fallback: an i64 product as perl' or diag explain $r;
    $r = $fallback->("$n my \$r = \$n * 2305843009213693952; print \"\$r\\n\";\n");
    is $r->{exit}, 255, 'the fallback: a product past IV_MAX stops' or diag explain $r;
    like $r->{out} // '', qr/refused at run time: an integer \+ - \* past what an i64 holds/, 'naming why';
    $r = $fallback->("$n my \$r = \$n + 9223372036854775804; print \"\$r\\n\";\n");
    is $r->{exit}, 255, 'the fallback: a sum past IV_MAX stops' or diag explain $r;
    $r = $fallback->("my \$x = 4611686018427387904; my \$r = \$x * 2; print \"\$r\\n\";\n");
    like $r->{why} // '', qr/GAP: an integer \+ - \* past what an i64 holds/, 'the fallback: literals past IV_MAX refused by name';
    $r = $fallback->("print 9223372036854775807 + 1, \"\\n\";\n");
    like $r->{why} // '', qr/GAP: an integer constant past what an i64 holds/, 'the fallback: a UV constant refused by name';
}

done_testing;
