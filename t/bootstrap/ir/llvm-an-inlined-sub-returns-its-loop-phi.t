# ABOUTME: An inlined sub returning a value its loop carries returns the loop's phi,
# ABOUTME: whatever ifs its body holds: through B::SoN -> chalk -> lli == perl.
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

# A LOOP PHI IS LOWERED WITH ITS LOOP. The arm guard walked a returned loop
# phi's back-edge into the body, found an if's merge there, and refused the
# sub as "made inside one of its arms" (19 pvm corpus cases). The phi is in
# the loop's header, which dominates what follows the loop on the sub's main
# chain; only its first value comes from outside.
for my $case (
    [ q{sub f { my $n = shift; my $s = 0; for my $i (1 .. $n) { if ($i % 2) { $s = $s + $i } } return $s } print f(5), " ", f(4), "\n";}, "9 4\n", 'an if in the body' ],
    [ q{sub f { my $n = shift; my $o = ""; for my $i (1 .. $n) { next if $i == 2; $o = $o . $i } return $o } print f(4), "\n";}, "134\n", 'a next in the body' ],
    [ q{sub f { my $n = shift; my $s = 0; if ($n > 2) { for my $i (1 .. $n) { $s = $s + $i } } return $s } print f(3), f(1), "\n";}, "60\n", 'a loop inside an if' ],
    [ q{sub f { my $n = shift; my $s = 0; while ($s < $n) { if ($s > 1) { $s = $s + 2 } else { $s = $s + 1 } } return $s } print f(6), "\n";}, "6\n", 'an if/else in a while' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
