# ABOUTME: A recursive sub or method whose parameters are references or objects: a
# ABOUTME: define taking each as a Scalar (%Slot), read by its tag in the body.
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
    [ q{sub sum { my ($t) = @_; return 0 unless $t; return $t->{v} + sum($t->{l}) + sum($t->{r}) } print sum({ v => 1, l => { v => 2 }, r => { v => 3, l => { v => 4 } } }), "\n";}, 'a tree walk' ],
    [ q{package C; sub new { bless {}, shift } sub f { my ($s, $n) = @_; return $n <= 0 ? 0 : $n + $s->f($n - 1) } package main; print C->new->f(3), "\n";}, 'a recursive method' ],
    [ q{sub depth { my ($l) = @_; return 0 unless ref $l; my $d = 0; for my $e (@$l) { my $x = depth($e); $d = $x if $x > $d } return $d + 1 } print depth([1, [2, [3]], [4]]), "\n";}, 'nested arrays: perl, or refused (a loop merge of the call nothing typed)' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    elsif ($name =~ /refused/) { like($@, qr/GAP/, "$name: refused by name") }
    else { fail("$name: perl's answer"); diag $@ }
}

done_testing;
