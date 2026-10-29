# ABOUTME: a loop phi with a Str start and an arithmetic back edge is a Scalar:
# ABOUTME: through B::SoN -> chalk -> lli == perl, or refused by name.
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

# `my $i = $ENV{N} // 3; ... $i = $i - 1 while $i > 0` carries a Str in and a
# number round: the back edge, nothing typed, was no repr the phi could take
# (pvm 326, "NumGt ... over a Unknown operand").
for my $case (
    [ q{my $i = $ENV{N_UNSET_FOR_TEST} // 3; print $i = $i - 1 while $i > 0; print "\n";}, "210\n", 'a // default counted down' ],
    [ q{my $s = $ENV{N_UNSET_FOR_TEST} // "1"; my $k = 0; while ($k < 3) { $s = $s * 2; $k++ } print "$s\n";}, "8\n", 'a Str doubled' ],
    [ q{my $i = $ENV{N_UNSET_FOR_TEST} // "2.5"; print $i = $i - 1, " " while $i > 0; print "\n";}, "1.5 0.5 -0.5 \n", 'a fractional Str counted down' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
