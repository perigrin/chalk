# ABOUTME: _resolve_direct_calls reaches its callee through the Call's target
# ABOUTME: edge whenever that edge exists, not through the graph-name hash.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use Scalar::Util qw(blessed refaddr);
use lib 'lib', 't/lib';

use Chalk::IR::Serialize::JSON ();
use Chalk::IR::Analysis ();

# A direct Call carries its callee METAOBJECT on `target`, and that metaobject
# holds the callee GRAPH. The graph-name hash is the same object reached a
# second way -- the `Map<String,Graph>` passed alongside that the T1 contract
# says must stop being how a pass reaches the rest of the program.
#
# MEASURED ORDERING CONSTRAINT, and it is why this pass keeps a name read.
# `Analysis::run` calls _resolve_direct_calls TWICE. The first call precedes
# _attach_call_targets (which needs the sealed MOP, and the MOP is sealed by
# _replay_classes after the field-type passes), so at that call EVERY direct
# Call has `target` undef -- the edge does not exist yet. Deleting the name
# read outright silences that first pass entirely; measured, it is where most
# direct-call result stamps come from, and `ir/llvm-class-sub-define.t` fails
# without it. So the edge is read WHEN IT EXISTS and the name read survives
# only as the pre-MOP bootstrap; retiring it is what Phase 5 does when
# _attach_call_targets can precede the first resolve.
#
# What this test pins is the half that IS resolvable now: once the edge
# exists, it -- and not the name -- is what the pass follows.

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

my $SRC = <<'SRC';
use 5.42.0;
sub f { my $x = shift; return $x + 1 }
my $a = f(1);
say($a);
SRC

my ($fh, $path) = tempfile(SUFFIX => '.pl', UNLINK => 1);
binmode $fh, ':utf8';
print $fh $SRC;
close $fh;

my $json = qx($PERL -I$SON -MO=SoN,json,package=main $path 2>/dev/null);
plan skip_all => 'producer emitted no JSON' unless ($json // '') =~ /\S/;

sub direct_calls ($gs) {
    my @out;
    for my $gname (sort keys $gs->%*) {
        for my $n ($gs->{$gname}->nodes->@*) {
            next
                unless blessed($n)
                && $n->operation eq 'Call'
                && $n->can('dispatch_kind')
                && ($n->dispatch_kind // '') eq 'direct';
            push @out, $n;
        }
    }
    return @out;
}

my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
my @calls  = direct_calls($graphs);

subtest 'the edge and the hash name the same graph object' => sub {
    plan skip_all => 'no direct call in the probe' unless @calls;
    for my $c (@calls) {
        ok($c->target, 'the direct Call carries a callee metaobject');
        my $by_edge
            = $c->target && $c->target->can('graph') ? $c->target->graph : undef;
        my $by_name = $graphs->{ $c->name // '' };
        ok($by_edge, 'the metaobject holds a graph');
        ok($by_name, 'the name hash holds a graph');
        is(refaddr($by_edge), refaddr($by_name),
            'edge and name lookup are the SAME object');
    }
};

subtest 'with the edge present, the name hash is not what is read' => sub {
    # Re-run the pass over a graph set whose callee is bound under a key no
    # Call names, with the Call's result repr cleared so the pass has work to
    # do. `$graphs->{$node->name}` misses; `$node->target->graph` does not.
    plan skip_all => 'no direct call in the probe' unless @calls;

    my %perturbed;
    for my $k ( sort keys $graphs->%* ) {
        $perturbed{ $k =~ /::f\z/ ? "shadow::$k" : $k } = $graphs->{$k};
    }

    my @c = grep { ( $_->name // '' ) =~ /::f\z/ } direct_calls( \%perturbed );
    ok( scalar @c, 'the perturbed set still has the direct call' );
    ok( $_->target, 'and it still carries its callee edge' ) for @c;

    # Clear the stamp the earlier full run already applied, so the assertion
    # below is about THIS pass's reading and not a leftover.
    $_->set_stamp(undef) for @c;
    Chalk::IR::Analysis::_resolve_direct_calls( \%perturbed );

    is( $_->stamp, 'Int',
        'the call result is stamped from the callee reached by EDGE' )
        for @c;
};

subtest 'the graph-name hash is not read AT ALL' => sub {
    # The stronger claim, and the one step 2 actually wants: not "the edge is
    # preferred" but "the name is never consulted". The fallback survived only
    # because _resolve_direct_calls was ALSO called once before
    # _attach_call_targets, so every Call reached it with target undef and took
    # the name path -- measured, exactly once per call, 18 times over the
    # corpus. Deleting that early call moved nothing (205 before and after),
    # so the fallback had no remaining reader and is gone.
    my $src = do {
        open my $fh, '<', 'lib/Chalk/IR/Analysis.pm' or die $!;
        local $/; <$fh>;
    };
    unlike($src, qr/\|\|\s*\$graphs->\{ \$node->name/,
           'no name-hash fallback remains in the resolve');

    # And the ordering that made it necessary must not come back: an early
    # resolve would silently re-introduce the fallback path.
    my ($attach_at) = $src =~ /\A(.*?)^\s+_attach_call_targets\(/ms;
    ok(defined $attach_at, 'the attach call is present');
    unlike($attach_at // '', qr/^\s+_resolve_direct_calls\(/m,
           'and no resolve runs before it');
};

done_testing;
