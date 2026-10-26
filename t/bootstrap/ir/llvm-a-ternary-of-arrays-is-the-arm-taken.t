# ABOUTME: `C ? @a : @b` in list context is the taken arm's elements, the other arm
# ABOUTME: never evaluated: B::SoN -> chalk -> lli == perl.
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

# Both arms Array: the select chain refused it ("mismatched or unsupported
# types (true=Array, false=Array)", pvm 199).
for my $c (
    [ q{my @a = (1, 2); my @b = (3); my $c = @ARGV ? 0 : 1; my @r = $c ? @a : @b; print "@r\n";} ],
    [ q{my @a = (1, 2); my $c = @ARGV ? 0 : 1; for my $e ($c ? @a : ()) { print $e } print "|"; for my $e (!$c ? @a : ()) { print $e } print "\n";} ],
    [ q{my @a = (1, 2); my @b = (3); my $c = @ARGV ? 1 : 0; print join(",", $c ? @b : @a), "\n";} ],
    [ q{sub f { my ($x, $c) = @_; my $s = ""; for my $e ($c ? @$x : ()) { $s .= $e } $s } print f([1, 2, 3], 1), "|", f([4], 0), "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
