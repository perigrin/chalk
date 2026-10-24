# ABOUTME: A value used inside an arm or a loop and again after it is lowered where
# ABOUTME: it dominates both: through B::SoN -> chalk -> lli == perl.
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

# HASH-CONSED VALUES CROSS STRUCTURE. The same `"$i"` stringification is
# `"b$i"` in an arm and `"c$i"` in a continue block; the same `my @a` is read
# in a loop body and interpolated after it. Lowered first inside, and cached,
# each was served where its definition did not dominate (pvm corpus 327 and
# 234, reached once `$"` and references lowered).
for my $case (
    [ q{my $n = $ENV{N} // 5; my $i = 0; my @s; while ($i < $n) {     $i = $i + 1;     next if $i == 2;     last if $i == 4;     push @s, "b$i"; } continue {     push @s, "c$i"; } print "@s\n";}, "b1 c1 c2 b3 c3\n", 'a value in an arm and in the continue block' ],
    [ q{sub w { $_[0][$_[1]] = "z"; 1 } sub f { my @a = qw(a b c); my $s = ""; my $i = 0; while ($i < 2) { my $v = $a[$i + 1]; if ($v ne "q") { w(\@a, $i + 1) } $s .= $v; $i++ } "$s @a" } print f(), "\n";}, "bc a z z\n", 'an array read in a loop and after it' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
