# ABOUTME: tr/// through T2: a graph of its own maps each character (a loop of
# ABOUTME: compares), in place or as a value, and counts what it matched.
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
for my $body (
    '(my $t = $s) =~ tr/a-c/A-C/; print "$t $s\n";',
    '$s =~ tr/a-z/A-Z/; print "$s\n";',
    'my $n = ($s =~ tr/0-9//); print "$n $s\n";',
    'my $u = $s =~ tr/abc/xy/r; print "$u $s\n";',
    '$s =~ tr/\-_/ab/; print "$s\n";',
) {
    my $r = tap("my \$s = \$ENV{S} // 'abc-d_e 123';\n$body\n");
    is $r->{verdict}, 'SAME', $body or diag $r->{why} // explain $r;
}
for my $f (qw(c d s)) {
    my $r = tap("my \$s = \$ENV{S} // 'aabbc';\n(my \$t = \$s) =~ tr/a-b//$f;\nprint \"\$t\\n\";\n");
    isnt $r->{verdict}, 'DIFFERS', "tr///$f: never a wrong answer" or diag explain $r;
}

done_testing;
