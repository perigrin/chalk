# ABOUTME: an argument nothing typed (it is tested for undef, or handed on)
# ABOUTME: is read as what the caller passed: compared, pushed, a hash key.
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


# B::SoN leaves a read untyped when a consumer takes it as it is (it may be
# undef); these consumers read the node's stamp, not the caller's value
# (pvm 069 137 139 154).
for my $src (
    q{sub f { my ($a, $b) = @_; if ($a > $b) { return $a } return $b } print f(1, 2), f(5, 3), f(2.5, 1), "\n";},
    q{use v5.42; no warnings; sub g ($x) { die "bad $x\n" if $x > 1; return $x } sub h ($x) { my $r = "n"; try { g($x); } catch ($e) { chomp $e; $r = "c:$e"; } return $r } $@ = "before"; print h(1), " ", h(2), " [$@]\n";},
    q{sub g { $_[1] + 2 } sub run { my ($in) = @_; my $pos = 0; my $out = ""; while ($pos < length $in) { my $c = substr($in, $pos, 1); if ($c eq "@") { $pos = g($in, $pos); next } $out .= $c; $pos++ } return $out } print run("ab\@xcd"), "\n";},
    q{sub walk { my ($op, $items) = @_; my @chain; if ($op eq "If" || $op eq "S") { push @chain, $op; return "stopped at @chain" if $op eq "If"; } for my $item (@$items) { push @chain, $item } return "@chain"; } print walk("If", [1]), " | ", walk("S", [2, 3]), " | ", walk("X", [4]), "\n";},
    q{my %P = (a => "b", b => "c", c => "d"); my %cache; sub is_sub { my ($child, $parent) = @_; my $current = $child; while (my $next = $P{$current}) { if ($next eq $parent) { $cache{"$child$parent"} = 1; return 1 } $current = $next } $cache{"$child$parent"} = 0; return 0 } print is_sub("a", "c"), is_sub("a", "x"), is_sub("c", "d"), " ", join(",", map { "$_=$cache{$_}" } sort keys %cache), "\n";},
) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $want = qx($^X $pl 2>/dev/null);
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
