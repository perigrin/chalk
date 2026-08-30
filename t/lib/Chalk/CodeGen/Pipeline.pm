# ABOUTME: The one end-to-end seam: wire JSON -> load -> select units -> lower each.
# ABOUTME: Every full-sequence assembler routes through here so later phases edit ONE site.
use 5.42.0;
use utf8;
use experimental 'class';

use Scalar::Util qw(blessed refaddr);
use Chalk::IR::Serialize::JSON ();
use Chalk::Target::LLVM ();

class Chalk::CodeGen::Pipeline;

# Per-graph transforms, threaded ONE GRAPH AT A TIME (D4 / spec section 2).
# A transform is `sub ($graph) { ...; return $graph }`. This is the slot T1,
# T2 and the optimizers land in; it is deliberately NOT a `($graphs, $mop)`
# whole-set signature, which is the defect (finding B1) that killed the
# previous decomposition -- a whole-set signature lets a pass reach the program
# through a Map<String,Graph> passed alongside instead of through the EDGES.
field $transforms :param :reader = [];

# run($json, $select, %opts) -> \@units
#
# $select is `sub ($graphs, $mop) { ... }` returning a list of [$label, $ret]
# pairs -- the caller decides WHICH units it wants lowered and what to call
# them. Each pair becomes one result hash:
#
#   { label => $label, ok => bool, ll => $llvm_ir_or_undef, err => $reason_or_undef }
#
# A unit whose lowering dies is recorded and the run CONTINUES: the hardest
# caller (Phase5LibCoverage) reports per-unit coverage and must not abort on
# the first failure.
#
# %opts is per-CALL configuration (D6), never constructor state:
#   program_mode => 1   suppress the Int:/Str: return-value epilogue
# Anything else in %opts is passed through to lower() verbatim.
#
# A load failure is reported, not thrown. With nothing loaded there are no
# units, so run() returns an empty list -- which is ALSO what a successful
# load selecting zero units returns. Callers that must tell those apart use
# run_detail, whose fourth value is the load error.
method run ($json, $select, %opts) {
    my ($units) = $self->_run($json, $select, %opts);
    return $units;
}

# run_detail($json, $select, %opts) -> (\@units, $graphs, $mop, $load_error)
#
# The same run, with the load result exposed for callers that need the graph
# or the MOP alongside the lowered output (error reporting, oracle plumbing).
method run_detail ($json, $select, %opts) {
    return $self->_run($json, $select, %opts);
}

method _run ($json, $select, %opts) {
    my $graphs;
    my $load_error;
    try {
        $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    }
    catch ($e) {
        $load_error = "from_json failed: $e";
    }
    # A FAILED load and a load that succeeded with an empty graph set are
    # different outcomes and must not collapse into one. Only the failure
    # nulls the $graphs slot; an empty-but-real set is returned as itself, so
    # a caller checking `defined $graphs` learns whether from_json ran.
    return ([], undef, undef, $load_error) if defined $load_error;
    return ([], $graphs, undef, undef) unless $graphs && $graphs->%*;

    # Per-graph transform threading (D4). Each transform sees ONE GRAPH at a
    # time, never the set. Applied before selection so a transform sees the
    # same graphs the selector will.
    #
    # The MOP edge is RE-ESTABLISHED after each transform rather than trusted
    # to survive it. A transform that returns a NEW Graph -- which CLAUDE.md's
    # immutability rule actively encourages, and which every optimizer pass
    # will do -- gets `undef` for $mop, because Graph's $mop is a plain :param
    # populated once by Analysis::run's sweep. Severing it is INVISIBLE to the
    # corpus gate: the pipeline's own $mop still lowers correctly and the
    # emitted IR is byte-identical, while every graph in the set has lost the
    # edge that spec section 2 says a pass reaches the program through.
    # Carrying it forward is what keeps `run($graph) -> $graph` honest.
    for my $i (0 .. $transforms->$#*) {
        my $t = $transforms->[$i];
        for my $name (sort keys $graphs->%*) {
            my $old = $graphs->{$name};
            # Attributed, because the wrong-return check below already goes to
            # the trouble of naming the graph and an exception should not be
            # anonymous by comparison. With several passes installed (T1, T2,
            # optimizers -- this slot's whole purpose) a bare "Can't call
            # method on an undefined value" says nothing about WHICH pass on
            # WHICH graph. The die still propagates: a transform failure is not
            # a per-unit lowering GAP and must never be recorded as one.
            my $new;
            try { $new = $t->($old) }
            catch ($e) {
                die "Pipeline: transform $i died on graph '$name': $e";
            }
            blessed($new) && $new->isa('Chalk::IR::Graph')
                or die "Pipeline: a transform returned "
                     . (defined $new ? "'$new'" : 'undef')
                     . " for graph '$name'; transforms are \$graph -> \$graph.\n";
            $new->set_mop($old->mop) unless defined $new->mop;
            $graphs->{$name} = $new;
        }
    }

    # Read the MOP AFTER the transforms, so a transform that legitimately
    # installs a new one is honoured. Every graph carries the same MOP, so any
    # answers -- sorted so the choice is deterministic, not hash-order.
    my @names = sort keys $graphs->%*;
    my $mop   = $graphs->{ $names[0] }->mop;

    # CHECKED, not assumed. The read above is sound only because Analysis::run
    # points every graph at ONE sealed MOP -- but this runs AFTER the
    # transforms, and a transform holds one graph at a time. A pass that
    # installs a MOP on a SUBSET (the natural shape for anything rewriting some
    # classes) leaves the set inconsistent, and nothing downstream can see it:
    # lower() takes a single mop, the IR still emits, and half the program is
    # compiled against a MOP it no longer points at. Every caller reads only
    # the lowered text, so no consumer can disagree with any other -- the
    # wrong-but-CONSISTENT answer this seam's review existed to find.
    for my $n (@names) {
        my $m = $graphs->{$n}->mop;
        next if (defined $m ? refaddr($m) : 0) == (defined $mop ? refaddr($mop) : 0);
        die "Pipeline: graph '$n' carries a different MOP than '$names[0]' -- "
          . "a transform installed a MOP on part of the graph set.\n";
    }

    my @units;
    for my $pair ($select->($graphs, $mop)) {
        my ($label, $ret) = $pair->@*;
        my $ll;
        my $err;
        try {
            $ll = Chalk::Target::LLVM->lower($ret,
                %opts, (defined $mop ? (mop => $mop) : ()));
        }
        catch ($e) { $err = $e }
        push @units, {
            label => $label,
            ok    => ($ll ? true : false),
            ll    => $ll,
            err   => $err // ($ll ? undef : 'lower produced no output'),
        };
    }
    return (\@units, $graphs, $mop, undef);
}
