# ABOUTME: A `next` from an if arm skips the rest of the pass, carrying what the pass had
# ABOUTME: changed by then into the next one: B::SoN -> chalk -> lli == perl.
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

# A `next` IN AN ARM jumps to the loop's latch, where every path that ends
# the pass meets: the arms that skip, and the body that ran to its end. The
# values the loop carries are merged there. One `next if` alone was already
# an if/else; a second, or one in a nested arm, was refused (pvm 007, 114,
# 116, 117).
for my $case (
    [ q{my $s = ""; for my $i (1 .. 6) { next if $i == 2; next if $i == 4; $s .= $i } print "$s\n";}, "1356\n", 'two nexts' ],
    [ q{my @out; for my $i (1 .. 6) { next if $i == 2; next if $i == 4; push @out, $i } print "@out\n";}, "1 3 5 6\n", 'two nexts over a push (pvm 007)' ],
    [ q{my $s=''; for my $i (1..6) { $s .= $i; if ($i == 2) { $s .= "a"; next } if ($i == 4) { $s .= "b"; next } $s .= "-" } print "$s\n";}, "1-2a3-4b5-6-\n", 'an arm that changes what it carries, then skips (pvm 116)' ],
    [ q{my ($s,$n)=('',0); my $i=0; while ($i < 6) { $i++; $n++; if ($i == 2) { $s .= "a"; next } if ($i == 4) { $n += 10; next } $s .= "-" } print "$s $n\n";}, "-a--- 16\n", 'in a while loop (pvm 117)' ],
    [ q{my $s=''; for my $i (1..5) { next if $i == 1; $s .= $i; last if $i == 3; next } print "$s\n";}, "23\n", 'beside a last (pvm 114)' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
