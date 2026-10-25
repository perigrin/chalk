# ABOUTME: An anonymous sub called while the sub that made it runs -- passed down as an
# ABOUTME: argument, or held in a lexical -- runs its body, reading what it captured.
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

# A CODE REFERENCE A CALLEE IS PASSED is called through its parameter, and
# a closure reads the variable it captured as it is when it runs (pvm 128).
for my $c (
    [ q{use v5.36; sub w ($cb) { $cb->(5) } print w(sub { $_[0] + 1 }), "\n";},                         "6\n",  'passed down and called' ],
    [ q{my $k = 3; my $f = sub { $_[0] * $k }; print $f->(2), "\n";},                                  "6\n",  'a capture read' ],
    [ q{my $k = 3; my $f = sub { $k }; $k = 4; print $f->(), "\n";},                                    "4\n",  'the capture as it is when called' ],
    [ q{use v5.42; sub walk ($cb) { join ",", grep { defined } map { $cb->($_) } (1, 2, 3) } sub only ($want) { walk(sub ($n) { $n == $want ? $n : undef }) } print only(2), only(3), "\n";}, "23\n", 'a callback over a parameter' ],
    [ q{use v5.36; sub w ($cb) { my $k = "in"; $cb->() } sub m2 { my $k = "out"; w(sub { $k }) } print m2(), "\n";}, "out\n", 'its own $k, not the callee\'s' ],
) {
    my ($src, $want, $name) = @$c;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# REFUSED by name: a code reference used other than by a call, and a closure
# that writes what it captured.
for my $c (
    [ q{sub mk { return sub { 1 } } my $f = mk(); print $f->(), "\n";}, 'a code reference that leaves where it is made' ],
    [ q{my $k = 1; my $f = sub { $k++ }; $f->(); print "$k\n";},      'a closure that writes its capture' ],
) {
    my ($src, $name) = @$c;
    eval { through_llvm($src) };
    like($@, qr/GAP: /, "$name: refused");
}

done_testing;
