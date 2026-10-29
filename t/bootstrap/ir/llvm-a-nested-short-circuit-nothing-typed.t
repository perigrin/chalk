# ABOUTME: a short-circuit nothing typed, nested in another, is the Scalar its arms are:
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

# `if ($c) { if ($a && $b) { ... } }` falling off its end returns the failed
# test: `$c && ($a && $b)`. The inner && was typed only once lowered, so the
# outer took it for Unknown and refused (pvm 174, "And.LHS[Scalar -> Unknown]").
for my $case (
    [ q{sub f { my ($c, $a, $b) = @_; if ($c) { if ($a && $b) { return "y" } } }
        my @r = map { scalar(f(@$_)) // "u" } [1, "P", 3], [1, "P", 0], [0, 1, 1]; print "@r\n";}, "y 0 0\n", 'a nested && falls off, by flattened arguments' ],
    [ q{sub f { my ($c, $a, $b) = @_; $c && ($a || $b) } my @x = (1, 0, "z"); my @y = (0, 1, 1); print f(@x), "|", f(@y), "\n";}, "z|0\n", 'an && over an ||' ],
    # A REFERENCE ARM is boxed to the Scalar too (pvm 143, "And.LHS[Boolean->Unknown]").
    [ q{use v5.42; my @ag; sub g ($e, $p, $ag) { if ($e == $p && $ag) { push $ag->@*, $e } } g(1, 1, \@ag); g(1, 2, \@ag); g(3, 3, \@ag); print "@ag\n";}, "1 3\n", 'an && of a comparison and an array reference' ],
    # A METHOD CALL NOTHING TYPED is typed once lowered -- a run-time dispatch a
    # Scalar, an inlined one its callee's (pvm 180, "grep test[Unknown->Boolean]").
    [ q{use Scalar::Util qw(blessed); package K { sub new { bless {}, shift } sub ok { 1 } } my @a = (K->new, 3, K->new); my @g = grep { blessed($_) && $_->ok } @a; print scalar(@g), "\n";}, "2\n", 'a grep test of blessed && a method' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    if (!defined $got && $@ =~ /GAP/ && $@ !~ /Unknown\]/) { pass("$name: refused by name"); diag $@; next }
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
