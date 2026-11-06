# ABOUTME: T2 slice 15 -- a package scalar (our $g, $::s, $Pkg::v) is one global %Slot every
# ABOUTME: sub reads and writes; perl's own ($/, $", $0...) and local are not this.
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
    [ q{our $g = 1; sub f { $g = $g + 1; return 0 } f(); $::s = 5; print $g, $::s, "\n";}, 'our and $::, written in a sub' ],
    [ q{our $n; print defined $n ? "d" : "u"; $n = "x"; print $n, "\n";}, 'undef until written' ],
    [ q{package P; our $v = 3; sub get { return $v } package main; $P::v = 7; print P::get(), $P::v, "\n";}, 'another package, by its full name' ],
    [ q{our $c = 0; sub bump { $c++ } for my $i (1 .. 3) { bump() } print "$c\n";}, 'incremented in a loop of calls' ],
    [ q{our $g = 1; sub f { $g = 7 } my $before = $g; f(); print "$before $g\n";}, 'a read kept across a call that stores it' ],
) {
    my ($src, $name) = @$case;
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($LAST_LL, qr/^; chalk T2/m, "$name: lowered through T2");
}

# local, and perl's own: perl's answer, or refused.
for my $src (q{our $x = 1; sub f { return $x } sub g { local $x = 2; return f() } print g(), f(), "\n";}, q{$, = "-"; print 1, 2; print "\n";}) {
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "perl's own or local: perl's answer") }
    else { like($@, qr/GAP|refused at run time|^lower: /, "perl's own or local: refused by name") }
}

done_testing;
