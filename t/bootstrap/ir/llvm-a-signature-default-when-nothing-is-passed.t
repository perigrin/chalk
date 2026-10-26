# ABOUTME: a sub with a signature called with no arguments takes its defaults (and a
# ABOUTME: default that calls a sub runs only then): B::SoN -> chalk -> lli == perl.
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

# A call with no arguments took a path that bound nothing: the parameter
# was "outside an emitted function body", and the default's test of @_
# reached @_ unbound (pvm 102).
for my $c (
    [ q{use v5.36; sub f ($x = 5) { $x + 1 } print f(), f(1), "\n";} ],
    [ q{use v5.36; sub f ($x = 2, $y = $x * 3) { "$x/$y" } print f(), " ", f(4), " ", f(4, 1), "\n";} ],
    [ q{use v5.36; sub f ($x = "d") { scalar(@_) . $x } print f(), f("p"), "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A DEFAULT THAT RUNS CODE is an if in the body on how many arguments @_
# holds; its merge with the parameter is untyped when nothing else types the
# parameter (refused as TOP). It must not be a different answer -- above all,
# g() must run only when nothing is passed.
for my $src (
    q{use v5.36; sub g { 5 } sub f ($x = g()) { $x + 1 } print f(), f(1), "\n";},
    q{use v5.36; our $c = 0; sub g { $c++; 5 } sub f ($x = g()) { $x + 1 } print f(), f(1), " c=$c\n";},
    q{use v5.36; our $c = 0; sub g { $c++; "d" } sub f ($x = g()) { "<$x>" } print f(), f("p"), " c=$c\n";},
) {
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, qx($^X -e '$src'), "perl's answer: $src") }
    else { like($@, qr/\S/, "refused: $src") }
}

done_testing;
