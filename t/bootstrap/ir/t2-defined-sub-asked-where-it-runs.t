# ABOUTME: `defined &NAME` the program may change (B::SoN's SubDefined): answered as
# ABOUTME: compiled when no graph that may change it runs, refused by name when one does.
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

# A MODULE SUB with an eval of code not known here, never called (Test::More's
# use_ok in a test that calls only is()): the answer holds. (The program's own
# subs are all loaded, so each counts as one that may run.)
my $lib = File::Temp::tempdir( CLEANUP => 1 );
open my $pm, '>', "$lib/EvalMod.pm" or die $!;
print $pm "package EvalMod; sub f { eval \$main::x } sub g { my \$c = sub { eval \$main::x }; \$c } sub h { 2 } 1;\n";
close $pm;
for my $src (
    qq{use lib "$lib"; use EvalMod; print defined &nope ? "y" : "n", defined &EvalMod::h ? "y" : "n", EvalMod::h(), "\\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

# One that runs may change it: refused, naming the question.
for my $src (
    q{sub f { eval $main::x } f(); print defined &nope ? "y" : "n", "\n";},
    q{*late = sub { 1 }; print defined &late ? "y" : "n", "\n";},
    qq{use lib "$lib"; use EvalMod; EvalMod::f(); print defined &nope ? "y" : "n", "\\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'REFUSED', "refused: $src" or diag explain $r;
    like $r->{why} // '', qr/defined &(?:main::)?(?:nope|late)/, 'naming `defined &NAME`';
}

done_testing;
