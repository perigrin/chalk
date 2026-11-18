# ABOUTME: wantarray is the context its call was made in -- 1, false, undef -- and undef
# ABOUTME: at the top level: B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

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


# wantarray had no lowering (pvm 271, 003).
for my $src (
    q{my $w = wantarray; my @seen = ($w); print scalar(@seen), defined $w ? "d" : "u", "\n";},
) {
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# caller at the top level is undef, and the empty list (pvm 272).
{
    my $src = q{my $s = caller; my @l = caller; my @one = $s; print scalar @one, " ", scalar @l, defined $s ? "d" : "u", "\n";};
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# T2 REFUSES THESE, each by its reason (only the retired fallback lowered
# them): refused by name, never a wrong answer.
{
    my $src = q{sub c { my $w = wantarray; defined $w ? ($w ? "list" : "scalar") : "void" } my @l = c(); my $s = c(); print "$l[0] $s\n";};
    my $got = eval { through_llvm($src) };
    ok(!defined $got, "T2 lowers no module for it: $src");
    like($@, qr/\Alower: GAP: T2: out of its slices \(\Qwantarray in a sub (T2 has no void context)\E\)/, "refused by T2's reason: $src");
}

done_testing;
