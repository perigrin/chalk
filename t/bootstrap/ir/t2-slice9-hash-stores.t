# ABOUTME: T2 slice 9 -- a store to a hash element through a reference; a read waiting
# ABOUTME: across one is refused, never made after it (it would see the new value).
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
    [ q{my $h = {}; $h->{a} = 1; $h->{b} = "x"; $h->{a} = 2; print $h->{a}, $h->{b}, defined $h->{c} ? "d" : "u", "\n";}, 'stores, a replaced value, a missing key' ],
    [ q{sub set { my ($h, $k, $v) = @_; $h->{$k} = $v; return 0 } my $h = {}; set($h, "x", 5); set($h, "y", 6); print $h->{x} + $h->{y}, "\n";}, 'a store in a sub, through its argument' ],
    [ q{package C { sub new { bless { n => 0 }, shift } sub inc { my $s = shift; $s->{n} = $s->{n} + 1; return $s->{n} } }
my $c = C->new; $c->inc; print $c->inc, "\n";}, 'an object updating itself' ],
) {
    my ($src, $name) = @$case;
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($LAST_LL, qr/^; chalk T2/m, "$name: lowered through T2");
}

# A READ WAITING ACROSS A STORE: perl's answer (the old value), or refused.
for my $case (
    [ q{my $h = {a => 1}; my $x = $h->{a}; $h->{a} = 2; print $x, $h->{a}, "\n";}, 'a read kept across a store' ],
    [ q{sub f { my ($h, $c) = @_; my $x = $h->{a}; if ($c) { $h->{a} = 9 } return $x } my $h = {a => 1}; print f($h, 1), $h->{a}, "\n";}, 'a store in an arm after a read' ],
    [ q{sub set { my ($h) = @_; $h->{a} = 2; return 0 } my $h = {a => 1}; my $x = $h->{a}; set($h); print $x, $h->{a}, "\n";}, 'a read kept across a call that stores' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    else { like($@, qr/GAP|refused at run time|^lower: /, "$name: refused by name") }
}

# KNOWN: T2 refuses this (a read waiting across a method call), and Context.pm,
# the fallback, reads the store: 55 for 15. Not T2's to fix by lowering it
# wrong; a T2 slice that settles the read takes it from Context.pm.
TODO: {
    local $TODO = 'Context.pm reads a store a method made through its invocant';
    my $src = q{package C { sub new { bless { n => 1 }, shift } sub bump { my $s = shift; $s->{n} = 5; return 0 } }
my $c = C->new; my $x = $c->{n}; $c->bump; print $x, $c->{n}, "\n";};
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "a read kept across a method that stores: perl's answer");
}

done_testing;
