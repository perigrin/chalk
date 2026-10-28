# ABOUTME: a loop phi nothing typed whose back-edge comes through the body's
# ABOUTME: merges and `next` arms is what its init and those arms carry.
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


# `$name` (undef, then an element) and `@params` (an array the body
# re-makes) carried through `next` and an if/elsif were the lattice TOP
# (pvm 215).
for my $src (
    q{sub f { my @body; my @params; my $name; for my $x (@_) { if (!ref $x) { next if $x eq "sub"; $name = $x; } elsif (ref $x eq "ARRAY") { if (@params) { @body = $x->@* } else { @params = $x->@* } } } return "$name|@params|@body"; } print f("sub", "n", [1, 2], [3, 4, 5]), "\n";},
    q{my $last; for my $w (qw(a b c d)) { next if $w eq "c"; $last = $w; } print "$last\n";},
) {
    my $want = qx($^X -e '$src' 2>/dev/null);
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
