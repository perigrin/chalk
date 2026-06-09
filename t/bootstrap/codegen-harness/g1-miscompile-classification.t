# ABOUTME: G.1 gate-hardening: lowered-but-lli-rejected .ll must be MISCOMPILE not GAP.
# ABOUTME: RED test verifying that MdtestCorpus classifies a malformed-IR case as MISCOMPILE.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';
use lib 't/lib';

use Chalk::CodeGen::Harness::LLVMDriver;
use Chalk::CodeGen::Harness::MdtestCorpus;

# G.1 (F3): a graph that LOWERS successfully but produces malformed IR (lli_exit != 0)
# must be classified as MISCOMPILE, NEVER as GAP.
#
# The distinction:
#   GAP     = lowering DIED (could not produce .ll at all)
#   MISCOMPILE = .ll was produced but lli rejected it (exit != 0)
#   GREEN   = .ll produced AND lli accepted AND lli==perl
#
# The original bug (pre-G.1): MdtestCorpus._run_l_verdict_check used
#   !emitted_for_every_construct => 'GAP'
# but emitted_for_every_construct is 0 for both a lowering failure AND
# a lowering-succeeded-but-lli-rejected case.  The former is GAP; the
# latter is MISCOMPILE.  The harness could not distinguish them.

# ---- fixture: build a minimal graph that lowers OK (returns an Int Constant) ----
# We want to test the classification logic, not the lowering itself.
# The fixture uses an ir block with a GOOD graph (lli accepts it) and
# checks GREEN. Then we test the new emission_meta.lli_exit-based discrimination
# by testing MdtestCorpus._run_l_verdict_check indirectly via a case struct
# that has a buildable graph but whose LLVMDriver run returns lli_exit!=0.

# Test 1: LLVMDriver emission_meta must expose lli_exit for classification.
# If lowering succeeds and lli exits nonzero, emission_meta must contain
# lli_exit != 0 and emitted_for_every_construct == 0, AND the llvm_text must
# be defined (the .ll was produced, just rejected).
subtest 'LLVMDriver exposes lli_exit in emission_meta' => sub {
    use Chalk::IR::NodeFactory;
    use Chalk::IR::Node::Constant;
    use Chalk::IR::Node::Return;

    my $fac = Chalk::IR::NodeFactory->new;
    my $c   = $fac->make('Constant', value => 42, const_type => 'integer');
    $c->set_representation('Int');
    my $ret = $fac->make_cfg('Return', inputs => [$c]);

    my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($ret);
    ok(defined $meta, 'emission_meta is defined');
    ok(exists $meta->{lli_exit} || exists $meta->{marked_unsupported},
        'emission_meta has lli_exit or marked_unsupported key');

    # If it lowered and lli ran, lli_exit should be present (may be 0 for good IR).
    if (!$meta->{marked_unsupported} && exists $meta->{lli_exit}) {
        is($meta->{lli_exit}, 0, 'good graph: lli exits 0');
        is($meta->{emitted_for_every_construct}, 1, 'good graph: emitted_for_every_construct=1');
    }
};

# Test 2: MdtestCorpus must expose lli_exit from emission_meta in the l_verdict result.
# After G.1, when LLVMDriver returns lli_exit != 0, the corpus gate must classify
# the case as MISCOMPILE — NOT as GAP.
#
# We test this by calling _run_l_verdict_check indirectly via run_case with a
# synthetic case whose ir block builds a valid graph, and verifying the new
# MISCOMPILE-label path is reachable.
#
# Since we cannot easily inject a malformed-IR node, we verify the gate's
# CURRENT behavior (pre-fix it should call GAP; post-fix it should call MISCOMPILE)
# by checking the meta exposed. This is the RED: the test asserts MISCOMPILE but
# the current code emits GAP, so it will fail until G.1 is fixed.
subtest 'MdtestCorpus classifies lowered-but-lli-rejected as MISCOMPILE not GAP' => sub {
    # Build a real corpus case whose ir block will lower OK but report lli_exit != 0.
    # We do this by monkey-patching LLVMDriver->run for this test to simulate
    # a "lowered but lli rejected" scenario.
    #
    # Approach: override LLVMDriver::run in a local scope to return a fake meta
    # where ll_text is defined (lowering succeeded) but lli_exit != 0.

    no warnings 'redefine';
    local *Chalk::CodeGen::Harness::LLVMDriver::run = sub {
        my ($class, $return_node, $opts) = @_;
        # Simulate: lowering succeeded, lli rejected (exit 1, malformed IR)
        my $L = Chalk::CodeGen::Harness::BehaviorRecord->new(
            return_values     => [],
            wantarray_context => 'scalar',
            stdout            => '',
            stderr            => 'lli: malformed IR',
            exception         => {
                kind    => 'string',
                class   => undef,
                message => 'lli exited 1: malformed IR',
            },
            object_state => {},
        );
        my $meta = {
            emitted_for_every_construct => 0,   # lli failed
            marked_unsupported          => 0,   # lowering did NOT die
            ll_text                     => 'define i64 @main() { INVALID }',  # .ll was produced
            runtime_free_fraction       => 1.0,
            lli_exit                    => 1,   # lli exit nonzero — key signal
        };
        return ($L, $meta);
    };

    use Chalk::CodeGen::Harness::BehaviorRecord;

    # Build a minimal ir block that has a buildable graph
    # so _run_l_verdict_check reaches the LLVMDriver->run call.
    my $case = {
        title        => 'synthetic-miscompile-test',
        source       => 'do { 42 }',
        behavior     => "return: Int:42\ncontext: scalar\n",
        ir           => "%c = Constant(42) :Int\nreturn %c\nL: GREEN\n",
        source_pos   => undef,
        behavior_pos => undef,
        ir_pos       => undef,
        _perl_actual => 'Int:42',
    };

    # Run via run_case (which internally calls _run_l_verdict_check)
    my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

    # After G.1: the l_verdict should be MISCOMPILE (lli_exit != 0 with defined ll_text)
    # Before G.1 (current): it will be FAIL with actual='GAP' (wrong classification)
    my $lv = $result->{l_verdict};
    ok(defined $lv, 'l_verdict result is defined');

    # The key assertion: actual should be MISCOMPILE, not GAP.
    is($lv->{actual}, 'MISCOMPILE',
        'lowered-but-lli-rejected case must be classified MISCOMPILE, not GAP')
        or diag("Got actual='${\($lv->{actual}//'undef')}', overall='$result->{overall}'",
                "\nfail_reasons: ", join('; ', @{$result->{fail_reasons}}));
};

done_testing();
