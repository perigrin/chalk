# ABOUTME: T1's exit report is a MEASUREMENT, not an assertion -- it says what
# ABOUTME: inference achieved without refusing to hand back the graph.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Transform::TypeInference;

# Spec §9.4. The report carries four numbers:
#   arrived_absent         -- the FRONTEND metric (step 2)
#   unknown_at_exit        -- what T1 could not determine
#   narrowed_count         -- what it improved
#   widened_without_merge  -- a SOUNDNESS violation: spec §3/§9.3 forbid
#                             widening a type without a merge requiring it
#
# NOT AN ASSERTION THAT MUST BE DISABLED. That is what
# `_assert_value_nodes_are_typed` already is -- present in Analysis.pm and
# commented out at the call site, because 18 cases fail its condition today.
# A check that must be switched off to ship is not a check; it is a wish. The
# report instead REPORTS, so the number is visible every run and can be driven
# down deliberately rather than being all-or-nothing.

my $T1 = 'Chalk::IR::Transform::TypeInference';

sub graph_of (@nodes) { return TestGraph->new([@nodes]) }

subtest 'the report carries all four spec 9.4 fields' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $n = $f->make('PadAccess', targ => 0, sigil => '$', symbol => 'x', inputs => []);
    my $t1 = $T1->new;
    $t1->run(graph_of($n));
    my $r = $t1->report;

    ok(defined $r, 'a report exists') or return;
    for my $k (qw(arrived_absent unknown_at_exit narrowed_count
                  widened_without_merge)) {
        ok(exists $r->{$k}, "report carries $k");
        ok(defined $r->{$k}, "$k is MEASURED, not left undef")
            or diag("$k is undef -- an absent measurement and a measured zero "
                  . "are different claims");
    }
};

subtest 'unknown_at_exit counts what T1 could not determine' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    # A bare PadAccess with no source: nothing can type it, so it stays Unknown.
    my $bare = $f->make('PadAccess', targ => 0, sigil => '$', symbol => 'y', inputs => []);
    my $t1 = $T1->new;
    $t1->run(graph_of($bare));
    is($t1->report->{unknown_at_exit}, 1,
       'a node still Unknown at exit is counted');

    # A node that arrives typed is not.
    my $typed = $f->make('PadAccess', targ => 1, sigil => '$', symbol => 'z', inputs => []);
    $typed->set_stamp('Int');
    my $t2 = $T1->new;
    $t2->run(graph_of($typed));
    is($t2->report->{unknown_at_exit}, 0, 'a typed node is not counted');
};

subtest 'narrowed_count counts what T1 improved' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $n = $f->make('PadAccess', targ => 0, sigil => '$', symbol => 'w', inputs => []);
    my $t1 = $T1->new;
    $t1->run(graph_of($n));
    # Entry normalization turns an absence into Unknown -- that is not a
    # narrowing, it is making an absence honest. Nothing was determined.
    is($t1->report->{narrowed_count}, 0,
       'normalizing an absence to Unknown is NOT a narrowing');
};

subtest 'widened_without_merge is a soundness counter, and reads zero' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $n = $f->make('PadAccess', targ => 0, sigil => '$', symbol => 'v', inputs => []);
    $n->set_stamp('Int');
    my $t1 = $T1->new;
    $t1->run(graph_of($n));
    is($t1->report->{widened_without_merge}, 0,
       'T1 widened nothing without a merge requiring it');
};

subtest 'the counters MOVE -- narrowing and widening are distinguished' => sub {
    # WITHOUT THIS the three subtests above are vacuous: T1's inference body is
    # empty today (step 4 moves the loader's Analysis call into it), so every
    # counter reads 0 whether it works or is hardcoded. This substitutes a body
    # that actually changes a stamp and checks the report follows.
    #
    # Overridden through the symbol table, not @ISA: `feature class` methods are
    # not overridable by subclassing, which cost two wrong readings before it
    # was noticed.
    my $f = Chalk::IR::NodeFactory->new;

    for my $case ( [ 'Scalar', 'Int',    1, 0 ],   # narrowing
                   [ 'Int',    'Scalar', 0, 1 ] ) # widening: a soundness fault
    {
        my ($from, $to, $want_narrow, $want_widen) = $case->@*;
        my $n = $f->make('PadAccess', targ => 0, sigil => '$', symbol => "v_$from", inputs => []);
        $n->set_stamp($from);

        {
            no warnings 'redefine';
            no strict 'refs';
            local *{'Chalk::IR::Transform::TypeInference::_infer'} = sub {
                my ($self, $g) = @_;
                $_->set_stamp($to) for $g->nodes->@*;
                return;
            };
            my $t1 = $T1->new;
            $t1->run(graph_of($n));
            is($t1->report->{narrowed_count}, $want_narrow,
               "$from -> $to : narrowed_count = $want_narrow");
            is($t1->report->{widened_without_merge}, $want_widen,
               "$from -> $to : widened_without_merge = $want_widen");
        }
    }
};

package TestGraph {
    sub new { my ($c,$n)=@_; return bless { nodes => $n }, $c }
    sub nodes { $_[0]{nodes} }
    sub mop   { undef }
}

done_testing;
