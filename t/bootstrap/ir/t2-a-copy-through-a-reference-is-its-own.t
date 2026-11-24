# ABOUTME: `my @c = @$l` / `my %c = %$h` is a copy made where it stands: counted, a later
# ABOUTME: store through the reference does not reach it (final audit 2026-11-24, class B).
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

# (Count read the source through the reference where the deref is not under
# strict refs -- `scalar(@c)` counted @$l after the push -- and a hash copy's
# count was the source hash's.)
for my $src (
    q{my $l=[1,2]; my @c=@$l; push @$l,3; print scalar(@c),"\n";},
    q{my $h={a=>1}; my %c=%$h; $h->{b}=2; print scalar(keys %c),"\n";},
    q{my $l=[1,2]; my $n=@$l; push @$l,3; my @c=@$l; push @$l,4; print $n, scalar(@c),"\n";},
    q{sub f { my $l=shift; my @c=@$l; push @$l,9; return scalar @c } print f([1,2]),"\n";},
    q{my @a=(1,2); my $r=\@a; my @c=@$r; push @a,3; print scalar(@c),"\n";},
    q{my $l=[1]; my @c=(@$l); my @d=(0,@$l); push @$l,2; print scalar(@c),scalar(@d),"\n";},
    q{use strict; my $l=[1,2]; my @c=@$l; push @$l,3; print scalar(@c), " @c\n";},
) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    my ( $v, $why ) = run_probe($pl)->@*;
    is( $v, 'SAME', "perl's answer: $src" ) or diag $why;
}

done_testing;
