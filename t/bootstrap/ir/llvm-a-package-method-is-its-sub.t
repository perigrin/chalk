# ABOUTME: A method call on a package (blessed-hash OO, not `class`) runs the package's sub
# ABOUTME: with the invocant first -- B::SoN -> chalk -> lli == perl, or refused by name.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# A PACKAGE'S METHOD IS ITS SUB. `$o->m(3)` and `O->m(4)` on a package with
# `sub m` are calls to O::m with the invocant as $_[0]; the class's vtable
# (built from `class` methods) has no such slot, and the call was refused
# as "absent from class 'O' vtable -- available methods: []" (7 pvm cases).
# The class is the one the producer states statically; a method the
# package does not define itself (inherited through @ISA) is refused.
for my $case (
    [ q{package O { sub new { bless {}, shift } sub m { "m$_[1]" } } my $o = O->new; print $o->m(3), O->m(4), "\n";}, "m3m4\n", 'on an object and on the class' ],
    [ q{package O { sub new { bless {}, shift } sub m { $_[1] = 9 } } sub f { my $o = O->new; my $x = 1; $o->m($x); return $x } print f(), "\n";}, "9\n", 'writing its argument (pvm)' ],
    [ q{use v5.42; package O { sub m { $_[1] } } print O->m(5), O->m(6), "\n";}, "56\n", 'a class method' ],
    [ q{package O { sub m { $_[1] * 2 } } print O->m(5) + O->m(6), "\n";}, "22\n", 'its result typed from the sub, read by arithmetic' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# AN INHERITED METHOD resolves through the parent B::SoN records for a
# constant @ISA (llvm-a-plain-package-inherits.t). It was refused here.
is(eval { through_llvm(q{package P { sub m { "p" } } package O { our @ISA = ('P'); sub new { bless {}, shift } } print O->new->m, "\n";}) },
    "p\n", "an inherited method: perl's answer") or diag $@;

done_testing;
