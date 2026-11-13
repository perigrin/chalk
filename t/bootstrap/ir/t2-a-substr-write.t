# ABOUTME: The four-argument substr through T2 -- substr($s, o, l, R), the write an
# ABOUTME: lvalue substr and an s/// into a substr are: the part replaced in place.
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

for my $src (
    q{my $p = "abcdef"; my $o = substr($p, 1, 2, "XYZ"); print "$p $o\n";},
    q{my $p = "abcdef"; substr($p, -2, 1, ""); print "$p\n";},
    q{my $p = "abcdef"; substr($p, 0, -1) = "Z"; print "$p\n";},
    q{my $p = "ab"; substr($p, 2, 5, "!"); print "$p\n";},
    q{my $c = "hello world"; substr($c, 5) = "..."; my $d = "abcdef"; substr($d, -2) = "!"; print "[$c][$d]\n";},
    q{my $p = "aXbXX"; substr($p, 0, -1) =~ s/X/Q/g; print "$p\n";},
    q{my $p = "aXbXX"; my $n = (substr($p, 0, 4) =~ s/X/Q/g); print "$n $p\n";},
    q{my $p = "aXbXX"; substr($p, 0, -1) =~ s/X/lc("Q") . "!"/ge; print "$p\n";},
    # File::Temp's _replace_XX: one-letter @CHARS, so rand picks the same.
    q{my @C = qw/Q/; sub r { my ($path, $ignore) = @_; my $end = ( $] >= 5.006 ? "\\\\z" : "\\\\Z" ); if ($ignore) { substr($path, 0, - $ignore) =~ s/X(?=X*$end)/$C[ int( rand( @C ) ) ]/ge } else { $path =~ s/X(?=X*$end)/$C[ int( rand( @C ) ) ]/ge } return $path } print r("aXbXXX", 0), " ", r("fXXXX.tmp", 4), "\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

done_testing;
