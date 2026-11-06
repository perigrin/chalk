# ABOUTME: T2 slice 10 -- a `my @a` declared once in its sub (not in a loop body or an arm)
# ABOUTME: is one array, made at its function's entry, read and pushed wherever it is named.
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
for my $case (
    [ q{my @r; for my $n (1 .. 3) { push @r, $n * 2 } print "@r ", scalar(@r), " $r[1]\n";}, 'pushed in a loop, read after' ],
    [ q{my @out; for my $i (1 .. 6) { if ($i != 2 && $i != 4) { push @out, $i } } print "@out\n";}, 'pushed in an arm in a loop' ],
    [ q{sub f { my @a; push @a, 1, 2; my $s = ""; for my $x (@a) { $s .= $x } return $s } print f(), f(), "\n";}, 'fresh each call of its sub' ],
    [ q{sub twice { return $_[0] * 2 } my @r; for my $n (1 .. 3) { push @r, twice($n) } print "@r\n";}, 'pvm 035' ],
    [ q{sub f { my ($a, $b) = @_; return ($a || $b) . "|" . ($b && 7) . "|" . ($a && 9) } print f(0, "x"), " ", f(3, ""), "\n";}, '&& and || are their operands' ],
) {
    my ($src, $name) = @$case;
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($LAST_LL, qr/^; chalk T2/m, "$name: lowered through T2");
}

done_testing;
