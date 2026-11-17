# ABOUTME: @{ $h{missing} } of an element read known undef is an empty list, as perl's
# ABOUTME: rvalue @{ undef } is; COUNTED it is undef, so a count is refused by name.
use 5.42.0;
use utf8;
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

# A read stamped Undef (its key known missing) was bitcast as an i8* -- an
# i1 where a ptr was wanted, invalid IR. Its program is T2's named refusal now,
# below.

# perl's scalar(@{ undef }) is undef ("" printed), not the 0 an empty array
# counts: refused, not answered.
{
    my $src = q{my %h = (n => [1]); print scalar(@{ $h{z} }), "\n";};
    my $got = eval { through_llvm($src) };
    like($@, qr/GAP: T2: out of its slices \(\Qa count of \E\@\Q{} over an element known undef\E\)/, "a count of \@{ undef } is refused by name");
}

# T2 REFUSES THESE, each by its reason (only the retired fallback lowered
# them): refused by name, never a wrong answer.
{
    my $src = q{my %h = (n => [1]); my @l = @{ $h{z} }; print scalar(@l), "|", join(",", @{ $h{z} }), "|", scalar(@{ $h{n} }), "|", join(",", @{ $h{n} }), "\n";};
    my $got = eval { through_llvm($src) };
    ok(!defined $got, "T2 lowers no module for it: $src");
    like($@, qr/\Alower: GAP: T2: out of its slices \(\Qa count of \E\@\Q{} over an element known undef\E\)/, "refused by T2's reason: $src");
}

done_testing;
