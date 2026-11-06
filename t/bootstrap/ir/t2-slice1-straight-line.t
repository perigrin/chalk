# ABOUTME: T2 slice 1 -- a straight-line program lowered through a graph typed in LLVM's
# ABOUTME: types (repr chosen there: a Str a Num reaches is a %Slot), printed; others fall back.
our $LAST_LL;
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
    $LAST_LL = $units->[0]{ll};
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

# Through T2: the module says so, and perl's answer comes out.
for my $case (
    [ q{print 1 + 2, "\n";}, 'integer arithmetic' ],
    [ q{my $x = 0.5; my $y = $x * 3; print $y, " ", $y + 1, "\n";}, 'numbers' ],
    [ q{my $s = "a" . "b"; print $s . "c", "\n";}, 'strings' ],
    [ q{my $n = 7; print $n > 3 ? "big" : "small", "\n";}, 'a ?: of strings' ],
    [ q{my $c = $ENV{NOPE} // 1; my $v = $c ? 0.1 + 0.2 : "x"; print $v == 0.3 ? "eq" : "ne", " $v\n";},
      'a Str a Num reaches is boxed (T1 Str, T2 %Slot)' ],
    [ q{my $d = $ENV{NOPE} // 4; print 1 / $d, "\n";}, 'division' ],
    [ q{my $s = $ENV{NOPE} // "0"; print $s ? "t" : "f", "\n";}, q{the truth of a string} ],
) {
    my ($src, $name) = @$case;
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($LAST_LL, qr/^; chalk T2/m, "$name: lowered through T2");
}

# Out of T2's slices (a regex match; a hash was, until slice 14): the
# fallback, unchanged.
{
    my $src = q{my $s = $ENV{NOPE} // "ab"; print $s =~ /b/ ? 21 : 2, "\n";};
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "a regex: perl's answer") or diag $@;
    unlike($LAST_LL, qr/^; chalk T2/m, 'a regex: not T2 (falls back)');
}


done_testing;
