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

done_testing;
