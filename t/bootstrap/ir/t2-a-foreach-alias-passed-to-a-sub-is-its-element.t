# ABOUTME: A foreach iterator aliased by reference, handed to a sub, is the element: the sub's $_[0]
# ABOUTME: sees a store to the element made before it reads (@_ taken as the array of aliases).
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
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

# (coordinator, after audit 4 -- probe x/xm27: `1` for perl's `5`. B::SoN passes
# the iterator as its read through the pass's element reference, which is no
# place, and f was made to take its argument by value: a copy.)
for my $src (
    q{our @a=(1); sub f { $a[0]=5; $_[0] } for my $x (@a) { print f($x) } print "\n";},
    q{my @a=(1); sub f { $a[0]=5; $_[0] } for my $x (@a) { print f($x) } print "\n";},
    q{our @a=(1,2); sub f { $a[$_[1]]=5; $_[0] } my $i=0; for my $x (@a) { print f($x, $i++) } print "\n";},
    q{our @a=(1,2); sub f { $a[0]=7; "$_[0]" } my @r; for my $x (@a) { push @r, f($x) } print "@r|@a\n";},
) {
    my $r = tap("$src\n");
    isnt $r->{verdict}, 'DIFFERS', "never a wrong answer: $src" or diag explain $r;
    is $r->{verdict}, 'SAME', "perl's answer: $src" or diag $r->{why} // explain $r;
}

done_testing;
