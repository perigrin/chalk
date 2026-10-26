# ABOUTME: a sort with a comparator inside a loop, its result walked by a map: the sort
# ABOUTME: is a memory version, not a value merged by a phi -- B::SoN -> chalk -> lli == perl.
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

# The map's memory phi took the sort (it runs code, so it is pinned and
# versions memory) as its memory; a builtin call was not counted one, so the
# phi was lowered as an untyped value: TOP (pvm 217).
for my $c (
    [ q{my @l; for my $c (1, 2) { my $fl = [{ i => 2 }, { i => 1 }]; my @s = sort { $a->{i} <=> $b->{i} } @$fl; push @l, join(",", map { $_->{i} } @s) } print "@l\n";} ],
    [ q{my @l; for my $c (3, 1) { my @s = sort { $b <=> $a } ($c, 2); push @l, join("", map { $_ * 2 } @s) } print "@l\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A VALUE merge over a sort is no memory merge: perl's answer, or refused.
{
    my $src = q{my $c = $ENV{NOPE} ? 1 : 0; my @s = $c ? sort { $a <=> $b } (2, 1) : (5); print "@s\n";};
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, qx($^X -e '$src'), "perl's answer: $src") }
    else { like($@, qr/\S/, "refused: $src") }
}

done_testing;
