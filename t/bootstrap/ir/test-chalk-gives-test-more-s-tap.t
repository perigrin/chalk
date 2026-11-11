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

# A VERSION ASKED OF IT (`use Test::More 0.88`) is one Test::Chalk answers:
# it stands in for Test::More of that version.
{
    my ( $fh, $tc ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh "use lib 't/lib';\nuse Test::Chalk 0.88;\nok(1);\ndone_testing;\n"; close $fh;
    is Chalk::CodeGen::Harness::TapDiff->compare($tc)->{verdict}, 'SAME', 'use Test::Chalk 0.88';
}
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


# THE MEDIUM TIER: isa_ok, can_ok, cmp_ok, skip.
my $classes = qq{package Foo;\nsub new { my (\$c) = \@_; return bless {}, \$c }\nsub bar { 1 }\npackage main;\n};
same_as_test_more( $classes . qq{my \$o = Foo->new;\nisa_ok(\$o, 'Foo');\nisa_ok(\$o, 'Bar');\nisa_ok(\$o, 'Foo', 'the thing');\nisa_ok(\$o, 'Bar', 'the thing');\ndone_testing;\n}, 'isa_ok an object' );
same_as_test_more( qq{my \$r = [];\nisa_ok(\$r, 'ARRAY');\nisa_ok(\$r, 'HASH');\nisa_ok(undef, 'Foo');\ndone_testing;\n}, 'isa_ok a reference and undef' );
same_as_test_more( $classes . qq{isa_ok('Foo', 'Foo');\nisa_ok('Foo', 'Bar');\ndone_testing;\n}, 'isa_ok a class' );
same_as_test_more( $classes . qq{can_ok('Foo', 'bar');\ncan_ok(Foo->new, 'bar', 'new');\ncan_ok('Foo', 'baz');\ncan_ok('Foo', 'x', 'new', 'y');\ndone_testing;\n}, 'can_ok' );
same_as_test_more( qq{my \$one = 1;\ncmp_ok(\$one, '==', 1, 'eq num');\ncmp_ok(\$one, '==', 2, 'ne num');\ncmp_ok(\$one, '<', 0);\ncmp_ok('a', 'eq', 'b');\ncmp_ok('a', 'lt', 'b');\ncmp_ok(3, '!=', 3);\ncmp_ok('a', 'ne', 'a');\ncmp_ok(2, '>=', 3, 'ge');\ncmp_ok(undef, '==', 0);\ncmp_ok('x', 'eq', undef);\ncmp_ok(2, '>', 1);\ncmp_ok(1, '<=', 1);\ncmp_ok('b', 'gt', 'a');\ncmp_ok('a', 'le', 'a');\ncmp_ok('b', 'ge', 'c');\ndone_testing;\n}, 'cmp_ok' );
# skip LEAVES ITS CALLER'S SKIP: BLOCK (`last SKIP` from inside the sub), which
# nothing compiles yet: refused by name -- the producer once dropped it, and
# the skipped tests ran.
{
    my ( $fh, $tc ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh "use lib 't/lib';\nuse Test::Chalk;\nSKIP: {\n    skip 'no reason', 2 if \$ENV{NOPE} // 1;\n    ok(0);\n}\ndone_testing;\n";
    close $fh;
    my $r = Chalk::CodeGen::Harness::TapDiff->compare($tc);
    is $r->{verdict}, 'REFUSED', 'skip: refused';
    like $r->{why} // '', qr/Test::Chalk::skip, which the program calls, is refused in its module: GAP: a `last` with no loop of its sub to leave/, '... by name';
}


# THE HARD TIER. is_deeply: Test::More's _deep_check, path and all (a hash's
# keys in sorted order: perl's order is its own, so only one differing key
# is compared here).
same_as_test_more( qq{is_deeply([1,2,3], [1,2,3], 'same');\nis_deeply([1,2,3], [1,2,4], 'arr');\nis_deeply({a=>1,b=>[1,2]}, {a=>1,b=>[1,3]}, 'hash');\nis_deeply([1,2], [1,2,3], 'len');\nis_deeply([1,2,3], [1,2], 'shorter');\nis_deeply({a=>1}, {a=>1,b=>1}, 'keys');\nis_deeply('x', 'y', 'scalar');\nis_deeply([undef], [0]);\nis_deeply([undef], [undef], 'undefs');\nis_deeply({a=>[{b=>[1]}]}, {a=>[{b=>[1]}]}, 'deep');\nis_deeply({a=>[{b=>[1]}]}, {a=>[{b=>[2]}]}, 'deep differ');\ndone_testing;\n}, 'is_deeply' );


# subtest: a code ref run as a test of its own, its TAP indented.
same_as_test_more( qq{subtest 'inner' => sub {\n    ok(1, 'i1');\n    ok(1, 'i2');\n};\nsubtest 'bad' => sub {\n    ok(0, 'b1');\n    diag("d");\n    note("n");\n};\nsubtest 'done' => sub { ok(1); done_testing; };\nok(1, 'after');\ndone_testing;\n}, 'subtest' );
same_as_test_more( qq{subtest 'outer' => sub {\n    ok(1, 'o1');\n    subtest 'nested' => sub { ok(1, 'n1'); is(1, 2, 'n2'); };\n};\ndone_testing;\n}, 'nested subtests' );


# like/unlike: each qr// a value whose matcher is its pattern's own graph
# (regexes as graphs), called where like matches.
same_as_test_more( qq{like('abc', qr/b/, 'has b');\nlike('abc', qr/x/, 'has x');\nunlike('abc', qr/x/);\nunlike('abc', qr/b/, 'no b');\nlike(undef, qr/x/);\nunlike(undef, qr/x/, 'undef unlike');\ndone_testing;\n}, 'like and unlike' );
same_as_test_more( qq{use v5.36;\nlike('a1b2', qr/^(\\\\w\\\\d)+\$/, 'pairs');\nlike('Hello', qr/hello/i, 'case');\nunlike("a\\\\nb", qr/a.b/, 'no newline');\ndone_testing;\n}, 'like with flags' );

done_testing;
