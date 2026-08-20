#!/usr/bin/env perl
# ABOUTME: A corpus ir block is a GRAPH SPEC, so it must satisfy the IR invariants.
# ABOUTME: Without this a spec can assert a shape the IR forbids and still read green.

use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::MdtestCorpus;

# ---------------------------------------------------------------------------
# WHY THIS EXISTS
#
# The corpus gate has three legs, and the invariant leg runs TypedInvariant on
# the PRODUCER's graph (son-corpus-wide.t:240). Nothing ran it on the graph the
# ir BLOCK describes. The shape leg builds that graph but only subset-matches
# it as text.
#
# Measured on D1f when it landed (54f9931a): DELETING its `predecessors:` line
# left all three legs green, and SWAPPING it to [%proj1, %proj0] -- an inverted
# arm pairing, exactly the defect class of 44d1fa8c and 9ce43cdd -- also left
# all three legs green. A spec could assert a graph the IR forbids and nothing
# would say so.
#
# That matters because a corpus case is a triple contract and the ir block is
# the half a human reads. A spec whose Phi pairs values to the wrong arms
# teaches the wrong shape to whoever reads it next, and the gate agrees with it.
#
# THIS IS ABOUT THE SPEC, NOT THE PRODUCER. The producer's graph is separately
# checked. What is new is that the SPEC BLOCK ITSELF must be a legal graph.
# ---------------------------------------------------------------------------

# A real branch merge in corpus syntax: the D1f shape, reduced.
sub spec_block ($preds) {
    return <<~"IR";
        %start = Start()
        %n     = Constant(5) :Int
        %zero  = Constant(0) :Int
        %cmp   = NumGt(%n, %zero) :Bool
        %c1    = Constant(1) :Int
        %c2    = Constant(2) :Int
        %spos  = Constant("pos\\n") :Str
        %sneg  = Constant("neg\\n") :Str
        %if    = If(%start, %cmp)
        %proj0 = Proj(%if, index: 0)
        %proj1 = Proj(%if, index: 1)
        %pr_pos = Print(%spos)
        %pr_neg = Print(%sneg)
        %region = Region(%pr_pos, %pr_neg)
        %phi   = Phi(%c1, %c2, region: %region$preds) :Int
        %co    = Coerce(%phi : Int -> Str) :Str
        %nl    = Constant("\\n") :Str
        %cat   = Concat(%co, %nl) :Str
        %p     = Print(%cat)
        return %p
        branch_control: %proj0 -> %pr_pos
        branch_control: %proj1 -> %pr_neg
        control: %region -> %p
        L: GREEN
        IR
}

subtest 'a spec block that records its arms is invariant-clean' => sub {
    my $r = Chalk::CodeGen::Harness::MdtestCorpus
        ->spec_invariant_check(spec_block(', predecessors: [%proj0, %proj1]'));
    is $r->{verdict}, 'PASS', 'a well-formed merge spec passes'
        or diag($r->{reason} // '');
};

subtest 'a spec block whose merge Phi records NOTHING is reported' => sub {
    # The exact mutation that stayed green across all three legs.
    my $r = Chalk::CodeGen::Harness::MdtestCorpus
        ->spec_invariant_check(spec_block(''));
    is $r->{verdict}, 'FAIL', 'a merge Phi with no predecessors FAILS the spec check';
    like +($r->{reason} // ''), qr/predecessor/i,
        'the reason names the missing predecessors';
};

subtest 'a declared-GAP block is exempt' => sub {
    # A pure-GAP block has no nodes to check; it must not FAIL, and it must not
    # be silently treated as a passing shape either.
    my $r = Chalk::CodeGen::Harness::MdtestCorpus
        ->spec_invariant_check("GAP: not lowered yet\nL: GAP\n");
    isnt $r->{verdict}, 'FAIL', 'a declared GAP is not a spec-invariant failure'
        or diag($r->{reason} // '');
};

subtest 'a spec block need NOT pin every effect to the control chain' => sub {
    # A spec is a SUBSET: it names the nodes the case is about and omits the
    # rest, which is why the shape leg is a subset match. Measured across the
    # corpus, 49 of 199 cases with Print/Call nodes leave at least one off
    # their `control:` line. Applying the control-chain invariant to spec
    # blocks failed 36 cases on the first run, all with this one message and
    # none a real defect.
    my $r = Chalk::CodeGen::Harness::MdtestCorpus->spec_invariant_check(<<~'IR');
        %start = Start()
        %s     = Constant("hi\n") :Str
        %unpinned = Print(%s)
        %s2    = Constant("bye\n") :Str
        %p     = Print(%s2)
        return %p
        control: %start -> %p
        L: GREEN
        IR
    is $r->{verdict}, 'PASS', 'an unpinned effect is not a spec failure'
        or diag($r->{reason} // '');
};

subtest 'the effect-chain exemption did NOT gut the other checks' => sub {
    # The guard that matters: exempting one invariant must not silently exempt
    # the rest. A Phi whose value count disagrees with its Region's arity is a
    # statement the SPEC makes and gets wrong, so it must still FAIL.
    my $r = Chalk::CodeGen::Harness::MdtestCorpus->spec_invariant_check(<<~'IR');
        %start = Start()
        %n     = Constant(5) :Int
        %zero  = Constant(0) :Int
        %cmp   = NumGt(%n, %zero) :Bool
        %c1    = Constant(1) :Int
        %spos  = Constant("pos\n") :Str
        %sneg  = Constant("neg\n") :Str
        %if    = If(%start, %cmp)
        %proj0 = Proj(%if, index: 0)
        %proj1 = Proj(%if, index: 1)
        %pr_pos = Print(%spos)
        %pr_neg = Print(%sneg)
        %region = Region(%pr_pos, %pr_neg)
        %phi   = Phi(%c1, region: %region, predecessors: [%proj0, %proj1]) :Int
        %co    = Coerce(%phi : Int -> Str) :Str
        %p     = Print(%co)
        return %p
        branch_control: %proj0 -> %pr_pos
        branch_control: %proj1 -> %pr_neg
        control: %region -> %p
        L: GREEN
        IR
    is $r->{verdict}, 'FAIL', 'a 1-value Phi over a 2-input Region still FAILS';
    like +($r->{reason} // ''), qr/pair by position|control input/,
        'and the reason is the arity disagreement, not the effect chain';
};

subtest 'an unbuildable block SKIPs rather than FAILs' => sub {
    # Unbuildability is the shape leg's business to report; this leg must not
    # double-report it as an invariant violation.
    my $r = Chalk::CodeGen::Harness::MdtestCorpus
        ->spec_invariant_check("%x = NoSuchOp(%nope)\nreturn %x\nL: GREEN\n");
    is $r->{verdict}, 'SKIP', 'an unbuildable spec SKIPs'
        or diag($r->{reason} // '');
};

done_testing;
