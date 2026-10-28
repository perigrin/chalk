# ABOUTME: `last LABEL` / `next LABEL` from an inner loop to an outer one: B::SoN -> chalk
# ABOUTME: -> lli == perl, or refused by name.
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

# The outer loop's value, carried out through the inner one, had a second
# use (the exit's merge, reached by `last O` from inside); taken for a
# condition's mutation it was lowered in the outer header, before the inner
# loop -- "Phi node encountered ... before its enclosing structure" (pvm 115).
for my $src (
    q{my $s=''; O: for my $i (1..3) { for my $j (1..3) { $s .= "$i$j "; if ($j == 2) { last O } else { next } } } print "$s\n";},
    q{my $s=''; O: for my $i (1..3) { for my $j (1..3) { next O if $j == 2; $s .= "$i$j " } } print "$s\n";},
    q{my $n = 0; O: for my $i (1..4) { for my $j (1..4) { last O if $i * $j > 6; $n++ } } print "$n\n";},
) {
    my $got = eval { through_llvm($src) };
    # perl reads the source from a file: `-e '$src'` lost its `''` to the shell.
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    if (defined $got) { is($got, qx($^X $pl), "perl's answer: $src") }
    else { like($@, qr/GAP:/, "refused by name: $src") }
}

done_testing;
