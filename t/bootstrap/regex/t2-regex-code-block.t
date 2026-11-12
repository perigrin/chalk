# ABOUTME: A regex code block `(?{ ... })` through T2 is a call in the match's graph:
# ABOUTME: run on the hit, once each, in order, where the pattern is all literal.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

for my $body (
    'print "ok\n" if $s =~ /a(?{ $n++ })a/; print "$n\n";',
    'print "ok\n" if $s =~ /x(?{ $n++ })y/; print "$n\n";',
    'print "ok\n" if $s =~ /(?{ $n .= "1" })a(?{ $n .= "2" })/; print "$n\n";',
    'print "ok\n" if $s =~ /(a)(?{ $n++ })b/; print "$n\n";',
    # A MATCH WHOSE BLOCK RUNS IS A STORE: a read before it is made before it.
    '$s =~ /a(?{ $n = 1 })/; my $u = $n + 1; $s =~ /a(?{ $n = 10 })/; print "$n $u\n";',
    'my $r = qr/a(?{ $n = $n + 1 })/; $s =~ $r; my $u = $n * 10; $s =~ $r; print "$n $u\n";',
) {
    my $r = tap("my \$n = 0; my \$s = \$ENV{S} // 'xaab';\n$body\n");
    is $r->{verdict}, 'SAME', $body or diag $r->{why} // explain $r;
    unlike $r->{why} // '', qr/T2: out of its slices/, '... through T2';
}

# HOW OFTEN A BLOCK RUNS ELSEWHERE IS PERL'S OPTIMIZER'S (each start it
# tries that reaches it): refused by name, never a count perl would not give.
my $r = tap(qq{my \$n = 0; my \$s = \$ENV{S} // 'xaab';\nprint "ok\\n" if \$s =~ /a+(?{ \$n++ })b/; print "\$n\\n";\n});
isnt $r->{verdict}, 'DIFFERS', 'a block in a pattern not all literal: no wrong count';
like $r->{why} // '', qr/optimizer/, '... refused by name';


# A BLOCK WHOSE BODY ITS MATCHER IS NOT GIVEN (a qr value matched elsewhere, a
# qr interpolated into a pattern) is refused: it once ran nothing, silently.
for my $src (
    q{my $n = 0; sub mk { return qr/a(?{ $n++ })/ } my $r = mk(); my $s = $ENV{S} // "a"; $s =~ $r; $s =~ $r; print "$n\n";},
    q{my $t = ""; my $r1 = qr/b(?{ $t .= 2 })/; my $s = $ENV{S} // "ab"; $s =~ /a(?{ $t .= 1 })$r1/; print "$t\n";},
) {
    my $r = tap("$src\n");
    isnt $r->{verdict}, 'DIFFERS', "no silent wrong: $src" or diag $r->{why};
}

done_testing;
