# ABOUTME: `*x = \EXPR` binds the name $x to the scalar EXPR refers to (B::SoN's EntryWrite binds):
# ABOUTME: later reads and stores of $x are that scalar's, never a reference stored into $x.
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

# (fourth final audit, X2: each printed SCALAR(0x...) for perl's value, or
# stored into the static $x and not the element)
for my $src (
    q{our $x = 1; *x = \42; print "$x\n";},
    q{our $x = 1; sub chg { *x = \99 } my $o = $x; chg(); print "$o$x\n";},
    q{our $x = 1; sub rd { $x } *x = \42; print rd(), "\n";},
    q{our $x = 1; sub rd { $x } sub chg { *x = \42 } my @l = (rd(), chg() && rd()); print "@l\n";},
    q{our $x = 1; my @a = (4,5); *x = \$a[1]; $x++; print "@a\n";},
    q{our $x = 1; our $y = 2; *x = \$y; $x = 7; print "$x$y\n";},
    q{our $x = 1; my $v = 3; *x = \$v; $v = 8; print "$x\n";},
) {
    my $r = tap("$src\n");
    isnt $r->{verdict}, 'DIFFERS', "never a wrong answer: $src" or diag explain $r;
    like $r->{why} // '', qr/out of its slices|GAP/, "refused by name: $src" if $r->{verdict} eq 'REFUSED';
}

is tap(qq{our \$x = 1; *x = \\42; print "\$x\\n";\n})->{verdict}, 'SAME', 'bound to a constant: its value';
is tap(qq{our \$x = 1; sub rd { \$x } sub chg { *x = \\99 } my \$o = rd(); chg(); print \$o, rd(), "\\n";\n})->{verdict}, 'SAME',
    'bound in a sub, read in another';
# (bound to a literal, the name is read-only: perl dies on the store. The
# wire gives a package store no line, so the message names none.)
for ( [ qq{our \$x = 1; *x = \\42; \$x++; print "\$x\\n";\n}, 'a store after a bind to a literal dies' ],
      [ qq{our \$x = 1; sub w { \$_[0] = 9 } *x = \\42; w(\$x); print "\$x\\n";\n}, '... and through \@_' ] ) {
    my $r = tap( $_->[0] );
    ok $r->{llvm}{exit} == 255 && $r->{perl}{exit} == 255 && $r->{llvm}{out} eq $r->{perl}{out}
        && $r->{llvm}{err} =~ /\AModification of a read-only value attempted/, $_->[1] or diag explain $r;
}
like tap(qq{our \$x = 1; *x = \\42; my \$r = eval { \$x = 3; 1 }; print \$r ? "ok" : "died", "\\n";\n})->{why} // '',
    qr/a store to a name a glob bind may give a literal, in a program with an eval/, '... refused where an eval would catch it';

done_testing;
