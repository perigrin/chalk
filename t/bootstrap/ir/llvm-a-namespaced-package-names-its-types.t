# ABOUTME: a package or class whose name has `::` gets LLVM types and globals
# ABOUTME: lli accepts: the names are quoted (`%"Foo::Bar.vt"`), not left bare.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

# The stash read keeps these on the Context path, which registers every
# package with a vtable and an object struct.
for my $src (
    qq{package Foo::Bar;\nsub f { 3 }\npackage main;\nour \$answer = 1;\nprint Foo::Bar::f(), exists \$::{answer} ? "y" : "n", "\\n";\n},
) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail( $json,
        sub ($g, $m) { my $x = $g->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $x->returns->[0] ]) },
        program_mode => 1 );
    my $u = $units->[0] // {};
    ok( $u->{ok}, 'it lowers' ) or diag $err // $u->{err};
    my ( $lf, $ll ) = tempfile( SUFFIX => '.ll', UNLINK => 1 );
    print $lf $u->{ll} // ''; close $lf;
    is( scalar qx(timeout 20 $LLI $ll 2>&1), scalar qx($^X $pl 2>&1), "perl's answer: " . ( $src =~ s/\n/ /gr ) );
}

done_testing;
