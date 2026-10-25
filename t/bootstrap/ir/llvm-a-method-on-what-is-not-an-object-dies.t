# ABOUTME: A method called on undef or a plain value dies, as perl's does, inside an eval
# ABOUTME: whose error nothing reads; one whose message would be seen is refused.
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

# `state $n`, `field $x`, `defer {...}` without their features are METHOD
# CALLS on what is not an object, and die (pvm 422 423 425). Their message
# names the file and line, which nothing here knows -- so the die is lowered
# only where nothing reads $@.
for my $c (
    [ q{sub c { state $n = 0; $n = $n + 1; return $n } my $r = eval { c() }; print defined $r ? "ran" : "died", "\n";}, "died\n", 'on an undefined package scalar' ],
    [ q{my $x; my $r = eval { field $x; 1 }; print defined $r ? "ran" : "died", "\n";},                              "died\n", 'on an undefined lexical' ],
    [ q{sub f { defer { print "D\n" } print "body\n" } eval { f() }; print "end\n";},                                "D\nbody\nend\n", 'on a plain value' ],
) {
    my ($src, $want, $name) = @$c;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# ITS MESSAGE SEEN is refused: read from $@, or printed by an uncaught die.
for my $c (
    [ q{my $x; eval { $x->m; 1 }; print "[$@]\n";}, 'its $@ read' ],
    [ q{my $x; $x->m; print "after\n";},           'outside an eval' ],
) {
    my ($src, $name) = @$c;
    eval { through_llvm($src) };
    like($@, qr/GAP: /, "$name: refused");
}

done_testing;
