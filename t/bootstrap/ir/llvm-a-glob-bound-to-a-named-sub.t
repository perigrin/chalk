# ABOUTME: `*name = \&other` at the top level (pvm 209): a call of name made after it
# ABOUTME: runs other; one made before it, or a binding in an arm, is refused.
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
    my ($efh, $ef) = tempfile(SUFFIX => '.err', UNLINK => 1);
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>$ef);
    my $perr = do { local $/; <$efh> } // '';   # (the producer's refusal, when it is the one)
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "load: no program graph: $perr" unless @$units;
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
    [ q{package A; sub rr { "rr$_[0]" }
package B; *rr = \&A::rr; sub f { return rr($_[0]) }
package main; *rr = \&A::rr; print B::f(3), rr(4), "\n";}, 'pvm 209' ],
    [ q{sub two { 2 * $_[0] } *dbl = \&two; print dbl(5), "\n";}, 'pvm 209 shape: in main' ],
    [ q{sub two { 2 * $_[0] } if ($ENV{NOPE}) { *dbl = \&two } print defined(&dbl) ? dbl(5) : "none", "\n";}, 'in an arm: refused by name' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    elsif ($name =~ /\Apvm/) { fail("$name: perl's answer"); diag $@ }
    else { like($@, qr/GAP|LOAD/, "$name: refused by name") }
}

done_testing;
