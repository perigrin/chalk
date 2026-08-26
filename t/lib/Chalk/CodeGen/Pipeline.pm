# ABOUTME: The one end-to-end seam: wire JSON -> load -> select units -> lower each.
# ABOUTME: Every full-sequence assembler routes through here so later phases edit ONE site.
use 5.42.0;
use utf8;
use experimental 'class';

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
# A load failure is reported, not thrown: every unit gets `ok => false` with
# the loader's error -- except that with nothing loaded there are no units, so
# the caller sees an empty list plus `load_error` from run_with_load_error.
method run ($json, $select, %opts) {
    my ($units, undef, undef) = $self->_run($json, $select, %opts);
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
    return ([], undef, undef, $load_error) unless $graphs && $graphs->%*;

    # The MOP arrives on the graphs, not in a second return slot. Every graph
    # carries the same one, so any graph answers -- sorted so the choice is
    # deterministic rather than hash-order.
    my $mop = $graphs->{ (sort keys $graphs->%*)[0] }->mop;

    # Per-graph transform threading (D4). Each transform sees ONE graph at a
    # time, never the set. Applied before selection so a transform sees the
    # same graphs the selector will.
    for my $t ($transforms->@*) {
        $graphs->{$_} = $t->($graphs->{$_}) for sort keys $graphs->%*;
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
