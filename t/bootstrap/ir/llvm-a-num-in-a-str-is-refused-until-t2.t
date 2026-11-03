# ABOUTME: a number read from a Str merge or list element a Num reaches is refused by
# ABOUTME: name until T2 boxes it -- read as %Str it was its printed digits (eq for ne).
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

sub through_llvm ($src, $env) {
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
    local @ENV{ keys %$env } = values %$env;
    my $out = qx(timeout 20 $LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return ($out, $pl);
}

sub perl_says ($pl, $env) {
    local @ENV{ keys %$env } = values %$env;
    return scalar qx($^X $pl 2>/dev/null);
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

# T1 types these Str (Num joined with Str); their repr must box the Num, which
# is T2's (perigrin). Until then a numeric read of one is refused, not answered
# from 15 printed digits: 0.30000000000000004 compared equal to 0.3.
for my $case (
    # Out of T2's slices (a list): the fallback refuses. A ?: -- in a sub
    # too -- is T2's, which boxes it (t2-slice1, t2-slice3).
    [ q{my @b = (0.1 + 0.2, "x"); print $b[0] == 0.3 ? "eq" : "ne", "\n";}, 'an element of numbers and strings' ],
) {
    my ($src, $name) = @$case;
    my ($got) = eval { through_llvm($src, {}) };
    like($@, qr/GAP: .*T2/, "$name, read as a number: refused by name") or diag "got: " . ($got // 'undef');
}

# Read as a string, the same values are right: perl prints 15 digits too.
{
    my $src = q{my @a = (42, 0.5, 'plain'); print $a[0], $a[1], $a[2], "\n";};
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), 'read as strings: perl\'s answer') or diag $@;
}

done_testing;
