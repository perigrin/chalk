# ABOUTME: Contract test for Chalk::CodeGen::Pipeline -- the single seam the five
# ABOUTME: end-to-end assemblers route through (load -> select units -> lower).
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;

require_ok('Chalk::CodeGen::Pipeline') or BAIL_OUT('no Pipeline module');

# A two-sub program: both subs are lowerable units, so a per-unit result list
# has two entries. `bad` returns a bare block value the backend GAPs on, which
# is what proves a dying unit does not abort its sibling.
my $prog = <<'PROG';
use 5.42.0;
use utf8;
package main;
sub good { my $x = 1; return $x + 1 }
sub also_good { my $y = 2; return $y + 2 }
PROG

my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
binmode $fh, ':utf8';
print $fh $prog;
close $fh;

my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
plan skip_all => "B::SoN produced no JSON" unless $json =~ /\S/;

# ---------------------------------------------------------------------------
# The per-unit contract: an arrayref of unit hashes, one per selected graph.
# ---------------------------------------------------------------------------
my $select = sub ($graphs, $mop) {
    return map { [ $_, $graphs->{$_}->returns->[0] ] }
           grep { $graphs->{$_}->returns->[0] }
           sort keys %$graphs;
};

my $units = Chalk::CodeGen::Pipeline->new->run($json, $select);

is(ref $units, 'ARRAY', 'run returns an arrayref of unit results');
is(scalar @$units, 3, 'three selected units (both subs + the entry graph) yield three results');

for my $u (@$units) {
    ok(exists $u->{label}, "unit has a label ($u->{label})");
    ok(exists $u->{ok},    'unit has an ok flag');
    ok(exists $u->{ll},    'unit has an ll slot');
    ok(exists $u->{err},   'unit has an err slot');
}

ok($units->[0]{ok}, "first unit lowered: $units->[0]{label}")
    or diag("err: $units->[0]{err}");
ok($units->[1]{ok}, "second unit lowered: $units->[1]{label}")
    or diag("err: $units->[1]{err}");

# ---------------------------------------------------------------------------
# A unit whose lowering dies yields ok => false WITHOUT aborting its sibling.
# The first selected unit is deliberately un-lowerable (an undef Return node).
# ---------------------------------------------------------------------------
my $poisoned = sub ($graphs, $mop) {
    my @names = sort keys %$graphs;
    return ( [ 'poisoned', undef ],
             map { [ $_, $graphs->{$_}->returns->[0] ] }
             grep { $graphs->{$_}->returns->[0] } @names );
};

my $mixed = Chalk::CodeGen::Pipeline->new->run($json, $poisoned);
is(scalar @$mixed, 4, 'a dying unit still produces a result row');
ok(!$mixed->[0]{ok}, 'the dying unit is ok => false');
ok(defined $mixed->[0]{err} && length $mixed->[0]{err},
   'the dying unit carries its error');
ok($mixed->[1]{ok}, 'the sibling after the dying unit still lowered');

# ---------------------------------------------------------------------------
# A load failure is reported, not thrown.
# ---------------------------------------------------------------------------
my $broken = Chalk::CodeGen::Pipeline->new->run('{"methods":{}}', $select);
is(ref $broken, 'ARRAY', 'an empty wire still returns an arrayref');
is(scalar @$broken, 0, 'no selected units means no result rows');


# ---------------------------------------------------------------------------
# The transform slot: PER GRAPH, one graph at a time.
#
# This is the whole T1/T2/Optimizers accommodation, and it is born in the
# spec-section-2 shape: a transform is `sub ($graph) { ...; return $graph }`.
# It is deliberately NOT `($graphs, $mop)` -- a whole-set signature is finding
# B1, the defect that killed the previous decomposition, because it lets a pass
# reach the program through a Map<String,Graph> passed alongside instead of
# through the EDGES the spec requires.
#
# Proving the seam does not require building T1: an identity transform must be
# invoked once per loaded graph and must not perturb the lowered output.
# ---------------------------------------------------------------------------
my $seen = 0;
my $identity = sub ($g) { $seen++; return $g };

my (undef, $loaded) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select);
my $graph_count = scalar keys $loaded->%*;
cmp_ok($graph_count, '>', 0, "the wire loaded $graph_count graphs (not a vacuous count)");

my $transformed = Chalk::CodeGen::Pipeline
    ->new(transforms => [ $identity ])->run($json, $select);

is($seen, $graph_count, 'the transform ran once PER GRAPH, not once per run');

# Byte-identical lowered output: an identity transform changes nothing.
is(scalar $transformed->@*, scalar $units->@*, 'same unit count with a transform');
for my $i (0 .. $#$units) {
    is($transformed->[$i]{label}, $units->[$i]{label}, "unit $i label unchanged");
    is($transformed->[$i]{ll}, $units->[$i]{ll},
       "unit $i lowered output is BYTE-IDENTICAL under an identity transform");
}

# The contract is per-graph: the transform receives a Graph, never the set.
my @arg_kinds;
Chalk::CodeGen::Pipeline->new(transforms => [ sub ($g) { push @arg_kinds, ref $g; $g } ])
    ->run($json, $select);
is(scalar @arg_kinds, $graph_count, 'one invocation per graph');
is_deeply([ grep { $_ ne 'Chalk::IR::Graph' } @arg_kinds ], [],
          'every transform argument is a Chalk::IR::Graph -- never a hash of them (D4/B1)');

# --- The MOP edge survives a transform that returns a NEW graph -----------
#
# CLAUDE.md's immutability rule tells every pass author to return new objects,
# and Graph's $mop is a plain :param populated once by Analysis::run. So the
# natural transform shape severs the edge spec section 2 says a pass reaches
# the program through -- and it does so INVISIBLY: the pipeline's own $mop
# still lowers, and the emitted IR stays byte-identical, so no corpus gate run
# can see it. Only an assertion INSIDE the selector can.
{
    my $fresh = sub ($g) {
        Chalk::IR::Graph->new(start => $g->start, returns => [ $g->returns->@* ]);
    };
    my ($n_total, $n_with_mop) = (0, 0);
    Chalk::CodeGen::Pipeline->new(transforms => [$fresh])->run($json, sub ($graphs, $mop) {
        for my $name (sort keys %$graphs) {
            $n_total++;
            $n_with_mop++ if defined $graphs->{$name}->mop;
        }
        return ();
    });
    cmp_ok($n_total, '>', 0, 'the fresh-graph transform reached a non-empty graph set');
    is($n_with_mop, $n_total,
       'every graph still carries the MOP edge after a transform returns a NEW Graph');
}

# A transform that does not return a Graph is refused BY NAME, not left to
# surface later as an unattributed method-call-on-undef.
{
    my $err;
    eval {
        Chalk::CodeGen::Pipeline->new(transforms => [ sub ($g) { return } ])
            ->run($json, $select);
        1;
    } or $err = $@;
    like($err, qr/transform returned/, 'a non-Graph transform return dies loudly');
    like($err, qr/for graph '/, 'and the failure names the offending graph');
}

done_testing;
