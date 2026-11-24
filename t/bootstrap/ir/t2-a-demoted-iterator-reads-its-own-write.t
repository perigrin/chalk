# ABOUTME: A foreach iterator kept in memory (in an eval body) and written by `op=` is read
# ABOUTME: back as written, and its element holds the write if a die ends the pass (final audit).
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

# (B::SoN stored the `op=` into the element and left the iterator's slot
# alone: the next read of $x was the pass's start, `[1][2]` for `[2][3]`.
# probes/f/n20 printed perl's answer only because its die never fired.)
for my $src (
    q{my @a=(1,2); eval { for my $x (@a) { $x+=1; print "[$x]" } }; print "@a\n";},
    q{my @a=(1,2); eval { for my $x (@a) { $x+=1; die "x\n" if $x == 2 } }; print "@a $@";},
    q{my @a=(1,2); eval { for my $x (@a) { $x*=5; die "x\n" if $x>5 } }; print "@a $@";},
    q{my @a=(1,2); eval { for my $x (@a) { $x*=5; die "x\n" } }; print "@a $@";},
) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    my ( $v, $why ) = run_probe($pl)->@*;
    is( $v, 'SAME', "perl's answer: $src" ) or diag $why;
}

done_testing;
