# ABOUTME: A bare block's redo from an arm nested in an arm (Carp's short_error_loc):
# ABOUTME: the Regions merging those ways round meet the latch one inside another.
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

my $f = q{my %CI = (a => 1);
sub f {
    my ($called, $lvl, @c) = @_;
    my $i = 0;
    {
        $i++;
        if ($i < 3) {
            if (@c) {
                redo if defined($called) && $CI{$called};
                redo unless 0 > --$lvl;
                last;
            }
            else { return 0 }
        }
        redo if $i < 5;
    }
    return $i;
}
};
for my $call ( q{f('a', 1, 1), f('b', 2, 1), f(undef, 0, 1), f('b', 0)}, q{f('b', 5, 1), f('a', 0, 1)} ) {
    my $r = tap("$f print $call, \"\\n\";\n");
    is $r->{verdict}, 'SAME', $call or diag $r->{why} // explain $r;
}
# A redo in an if with no else, nested in a loop arm.
{
    my $r = tap(q{my $s = ""; my $i = 0; { $i++; if ($i < 6) { if ($i % 2) { $s .= "o"; redo } else { $s .= "e"; redo if $i < 4; last } } $s .= "-" } print "$s\n";} . "\n");
    is $r->{verdict}, 'SAME', 'redo and last in a nested if/else' or diag $r->{why} // explain $r;
}

done_testing;
