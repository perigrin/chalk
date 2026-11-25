# ABOUTME: Where the program aliases $_ and writes it, $_ is an alias (as an element of @_ is):
# ABOUTME: a write through it is the element; one B::SoN cannot follow is refused by name.
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
    [ q{sub bump { $_ .= "!" } sub f { my @a = (1, 2); $_ = "top"; bump() for @a; return "$_|@a" } print f(), "\n";},
      'a sub writing $_ for each element' ],
    [ q{my @a = (1, 2); for (@a) { $_ .= "x" } print "@a\n";},
      'the body writing $_' ],
    [ q{sub bump { $_ .= "!" } my @a = (1, 2); my @b = ("a", "b"); for (@a) { bump(); for (@b) { bump() } bump() } print "@a @b $_\n";},
      'nested aliases, each put back' ],
    [ q{sub bump { $_ .= "!" } $_ = "top"; my @a = (1); for (@a) { bump() } print "$_ @a\n"; bump(); print "$_\n";},
      '$_ itself outside the loop' ],
    [ q{sub show { print "[$_[0]]" } sub bump { $_ .= "!" } my @a = (1, 2); for (@a) { bump(); show($a[0]) } print "\n@a\n";},
      'an element read by its name after the write' ],
    [ q{sub bump { $_ .= "!" } my @a = (1, 2); my $c = 0; for (@a) { $c++ if $a[0] eq "1"; bump(); $c++ if $a[0] eq "1!"; } print "$c @a\n";},
      'an element read before and after the write' ],
);

for my $case (@same) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $name or diag $r->{why} // explain $r;
}

my @refused = (
    [ q{sub bump { $_ .= "!" } bump() for 1, 2; print "never\n";},
      'a literal aliased and written (perl dies)' ],
    [ q{sub show { print "[$_[0]]" } sub bump { $_ .= "!" } my @a = (1, 2); for (@a) { bump(); show($_) } print "\n@a\n";},
      'a read of $_ B::SoN folds to the element, after a sub wrote it' ],
    [ q{sub bump { $_ .= "!" } my @a = (1, 2); my @b = map { bump(); $_ } @a; print "@a|@b\n";},
      'map\'s $_ written by a sub, then read' ],
    [ q{sub bump { $_ .= "!" } my $x = "a"; for ($x) { bump() } print "$x\n";},
      'a variable aliased and written by a sub' ],
    [ q{sub bump { $_ .= "!" } my %h = (k => 1); for (values %h) { bump() } print "$h{k}\n";},
      'a hash\'s values aliased and written' ],
);

for my $case (@refused) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    isnt $r->{verdict}, 'DIFFERS', "$name: never a wrong answer" or diag explain $r;
    # (by T2, or by B::SoN where its rule names the case first: audit 2, K3 --
    # `$_` read after a call that may store its list)
    like $r->{why} // '', qr/T2: out of its slices|GAP: a foreach, map or grep's \$_ \(or a package iterator\) read after a call that may store its list/,
        "$name: refused by name" if $r->{verdict} eq 'REFUSED';
}

done_testing;
