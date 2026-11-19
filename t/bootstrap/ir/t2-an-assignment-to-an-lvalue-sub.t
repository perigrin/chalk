# ABOUTME: `f() = v` (perl compiles it only for an :lvalue sub): the sub runs, and v is stored
# ABOUTME: into the variable it ends at -- one of the file or a package; another is refused.
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


my @same = (
    [ q{my $slot = 0; sub slot :lvalue { $slot } slot() = 42; print slot(), "\n"; my $anon = sub :prototype($) { $_[0] * 2 }; print $anon->(21), "\n";},
      'a file lexical, then a prototyped closure' ],
    [ q{my $slot = 0; sub slot :lvalue { $slot } slot() = 42; print "$slot\n";},
      'the file lexical read by its name' ],
    [ q{our $g = 1; sub g :lvalue { $g } print "$g\n"; g() = 5; print "$g ", g(), "\n";},
      'a package scalar' ],
    [ q{my $slot = 1; sub slot :lvalue { $slot } my $before = $slot; slot() = 42; my $after = $slot; print "$before $after\n";},
      'read before and after' ],
);

for my $case (@same) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $name or diag $r->{why} // explain $r;
}

my @refused = (
    [ q{my $n = 0; sub s1 :lvalue { $n++; my $x = 3; $x } s1() = 7; print "$n\n";},
      'a sub\'s own variable' ],
);

for my $case (@refused) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    isnt $r->{verdict}, 'DIFFERS', "$name: never a wrong answer" or diag explain $r;
    like $r->{why} // '', qr/T2: out of its slices/, "$name: refused by name" if $r->{verdict} eq 'REFUSED';
}

done_testing;
