# ABOUTME: Test::Chalk through B::SoN, T2 and lli gives the TAP, diagnostics and exit
# ABOUTME: status Test::More gives perl: each function proved here before it is added.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

# THE ORACLE IS TEST::MORE: each probe runs once with `use Test::More` under
# perl, and once with `use Test::Chalk` through T2; the bytes must match.
sub same_as_test_more ($body, $name) {
    my ( $fh, $tc ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh "use lib 't/lib';\nuse Test::Chalk;\n$body";
    close $fh;
    my ( $gh, $tm ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $gh "use lib 't/lib';\nuse Test::More;\n$body";
    close $gh;
    my $r = Chalk::CodeGen::Harness::TapDiff->compare($tc);
    my $want = { Chalk::CodeGen::Harness::TapDiff::_run("$^X $tm") };
    # (the file name differs: the Test::More copy's is replaced by ours)
    $want->{err} =~ s/\Q$tm\E/$tc/g;
    is $r->{verdict}, 'SAME', "$name: perl and T2 agree on Test::Chalk" or diag $r->{why};
    is_deeply $r->{llvm} // {}, $want, "$name: ... and give Test::More's bytes";
}

same_as_test_more( qq{ok(1, 'a');\nok(1);\ndone_testing;\n}, 'ok passing' );
same_as_test_more( qq{ok(1, 'a');\nok(0, 'b');\nok(0);\ndone_testing;\n}, 'ok failing, with and without a name' );
same_as_test_more( qq{my \$nope = \$ENV{NOPE};\nok(\$nope, 'c');\ndone_testing;\n}, 'one failure: "test", not "tests"' );


# THE REST OF THE EASY TIER: is, isnt, pass, fail, diag, note, plan, BAIL_OUT.
same_as_test_more( qq{pass('f');\nfail('g');\npass;\ndone_testing;\n}, 'pass and fail' );
same_as_test_more( qq{my \$one = 1;\nis(\$one, 1, 'a');\nis(\$one, 2, 'c');\nis(undef, 'x', 'd');\nis('x', undef);\nis(undef, undef, 'both undef');\nis('', undef, 'empty is not undef');\ndone_testing;\n}, 'is' );
same_as_test_more( qq{isnt(3, 4, 'n');\nisnt(3, 3, 'e');\nisnt(undef, undef);\nisnt(undef, 0, 'u');\ndone_testing;\n}, 'isnt' );
same_as_test_more( qq{diag("hi");\ndiag("a", "b");\nnote("n1");\nok(1);\ndone_testing;\n}, 'diag and note' );
same_as_test_more( qq{plan(tests => 2);\nok(1);\nok(1, 'two');\n}, 'a plan first' );
same_as_test_more( qq{plan(skip_all => 'not here');\nok(1);\n}, 'skip_all' );
same_as_test_more( qq{ok(1);\nBAIL_OUT('stop');\nok(1);\n}, 'BAIL_OUT' );

done_testing;
