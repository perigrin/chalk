# ABOUTME: A tie of a scalar (Analysis rewrites its read as FETCH on the tie's object):
# ABOUTME: the tie calls the class's TIESCALAR with its arguments, the object its value.
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

for my $case (
    [ q{package Counter; sub TIESCALAR { return bless {}, "Counter" } sub FETCH { return 42 }
        package main; tie my $x, $ENV{X} // "Counter", "a", "b"; print $x, "\n";}, 'pvm tie:1' ],
    [ q{package Counter; sub TIESCALAR { return bless {}, "Counter" } sub FETCH { return 42 }
        package main; tie my $x, $ENV{X} // "Counter"; my $plain = 1; print tied($x) ? "t" : "u", tied($plain) ? "t" : "u", "\n";}, 'pvm tie:2' ],
    [ q{package C; sub TIESCALAR { my ($c, @a) = @_; print "tie $c @a\n"; return bless { n => scalar(@a) }, $c } sub FETCH { "n=" . $_[0]{n} }
        package main; tie my $v, "C", 1, 2, 3; print "$v\n", ref(tied($v)), "\n";}, 'TIESCALAR gets the class and the arguments' ],
    [ q{package D; our @ISA = ("B"); package B; sub TIESCALAR { bless [7], $_[0] } sub FETCH { $_[0][0] * 2 }
        package main; my $o = tie my $w, "D"; print ref($o), " $w\n";}, 'an inherited TIESCALAR, the tie\'s value' ],
) {
    my $r = tap("$case->[0]\n");
    is $r->{verdict}, 'SAME', $case->[1] or diag $r->{why} // explain $r;
}

done_testing;
