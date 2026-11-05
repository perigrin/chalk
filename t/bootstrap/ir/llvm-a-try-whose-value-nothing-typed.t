# ABOUTME: An eval that can die whose value nothing typed: a Scalar, the body's value or
# ABOUTME: undef where a die was caught; a dispatch that can die inside one is caught or refused.
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
    [ q{use v5.42; no warnings;
package S { sub new { bless {}, shift } sub add { my ($s, $a, $b) = @_; die "clash\n" if $a eq $b; return "$a$b" } }
sub merge ($s, $x, $y) {
    my $out = "none";
    if (defined $x) {
        my $merged;
        try { $merged = $s->add($x, $y); } catch ($e) { die "Ambiguity for '$x': $e"; }
        $out = $merged;
    }
    return $out;
}
my $s = S->new;
print merge($s, "a", "b"), " ", merge($s, undef, "b"), " ", (eval { merge($s, "a", "a") } // "died: $@");}, q{pvm 136: perl, or refused (its $@ is read)} ],
    [ q{package S { sub new { bless {}, shift } sub add { my ($s, $a, $b) = @_; die "clash\n" if $a eq $b; return "$a$b" } }
my $s = S->new; my $m = eval { $s->add("a", $ARGV[0] // "b") }; print defined $m ? $m : "undef: $@";}, 'an eval of a method that can die: perl, or refused' ],
    [ q{sub f { my ($a) = @_; die "z\n" if $a == 2; $a } my $v = eval { f(1) } ; my $w = eval { f(2) }; print "$v ", defined $w ? 1 : 0, " $@";}, 'an eval of a sub that can die' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    elsif ($name =~ /refused/) { like($@, qr/GAP/, "$name: refused by name") }
    else { fail("$name: perl's answer"); diag $@ }
}

done_testing;
