# ABOUTME: The MOP is the unit handle -- a graph reaches its siblings THROUGH
# ABOUTME: the edge it already carries, never through a hash passed alongside.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';
use JSON::PP;
use File::Temp qw(tempfile);
use Chalk::IR::Serialize::JSON ();

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "perl 5.42 not found"         unless -x $PERL;

# T1 spec §6: "With the MOP on the IR, a Call can answer 'what does my callee
# return' from the graph it is already in, and T1 needs no set. Without it, the
# only way to reach a callee is a lookup in a hash somebody passed alongside --
# which is the graph-set shape §2 rejects."
#
# perigrin RULED (2026-08-27) that the MOP gets a unit-level GRAPH REGISTRY,
# populated where the set_mop sweep already runs and attached by the LOADER so
# it survives the split. That satisfies §2's real prohibition -- no
# Map<String,Graph> in a PUBLIC signature -- because the registry is reached
# THROUGH the edge rather than passed beside it.
#
# What this does NOT change: the %graphs hash the existing passes take stays
# PRIVATE to Analysis.pm. Its elimination is filed separately (§11).

my $prog = <<'PROG';
use 5.42.0;
package main;
sub helper { return 1 }
sub caller_of { return helper() }
say(caller_of());
PROG

my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
print $fh $prog;
close $fh;
my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
plan skip_all => "B::SoN produced no JSON" unless $json =~ /\S/;

my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
my ($any) = map { $graphs->{$_} } sort keys %$graphs;

subtest 'the MOP carries the unit graph registry' => sub {
    my $mop = $any->mop;
    ok(defined $mop, 'the graph carries its MOP edge');
    ok($mop->can('graphs'), 'the MOP answers ->graphs')
        or return;
    my $reg = $mop->graphs;
    is(ref $reg, 'HASH', 'the registry is a name -> graph map');
    ok(scalar(keys %$reg) >= 2, 'it holds the unit\'s graphs')
        or diag("registry keys: " . join(',', sort keys %$reg));
};

subtest 'a graph reaches a SIBLING through the edge alone' => sub {
    # The §6 property, stated as a traversal: starting from ONE graph and
    # nothing else, every other graph in the unit is reachable. This is what
    # makes T1's one-graph contract possible rather than merely honest.
    my $mop = $any->mop or plan skip_all => 'no MOP edge';
    $mop->can('graphs') or plan skip_all => 'no registry yet';
    my $reg = $mop->graphs;
    for my $want (sort keys %$graphs) {
        ok(exists $reg->{$want}, "'$want' is reachable from a sibling")
    }
};

subtest 'the registry names the SAME objects, not copies' => sub {
    my $mop = $any->mop or plan skip_all => 'no MOP edge';
    $mop->can('graphs') or plan skip_all => 'no registry yet';
    my $reg = $mop->graphs;
    require Scalar::Util;
    for my $n (sort keys %$graphs) {
        next unless exists $reg->{$n};
        is(Scalar::Util::refaddr($reg->{$n}), Scalar::Util::refaddr($graphs->{$n}),
           "'$n' in the registry IS the loaded graph");
    }
};

done_testing;
