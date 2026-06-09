# ABOUTME: G.2 gate-hardening: central mechanical libperl-free guard on every GREEN verdict.
# ABOUTME: RED test verifying that a GREEN case with a libperl symbol in its .ll FAILS.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';
use lib 't/lib';

use Chalk::CodeGen::Harness::LLVMDriver;
use Chalk::CodeGen::Harness::MdtestCorpus;
use Chalk::CodeGen::Harness::BehaviorRecord;
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Return;

# G.2 (F4): every GREEN corpus case must pass a central mechanical libperl-free guard.
# The guard greps the emitted .ll for libperl symbols:
#   Perl_  \bSV\b  sv_  \bAV\b  \bHV\b  \bPL_  newSV  libperl
#
# Before G.2: 5/12 corpus .t files had no such assertion at all;
# the rest had inconsistent per-.t unlike() calls. A libperl leak in
# those GREEN cases would ship uncaught.
#
# After G.2: the guard lives in LLVMDriver (or MdtestCorpus) so ANY GREEN
# is automatically checked regardless of which .t file invokes it.

# Test 1: a clean .ll (no libperl symbols) passes the guard (must stay GREEN).
subtest 'clean .ll passes libperl-free guard' => sub {
    my $fac = Chalk::IR::NodeFactory->new;
    my $c   = $fac->make('Constant', value => 7, const_type => 'integer');
    $c->set_representation('Int');
    my $ret = $fac->make_cfg('Return', inputs => [$c]);

    my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($ret);
    ok(!$meta->{marked_unsupported}, 'lowering did not GAP');
    is($meta->{lli_exit} // 0, 0, 'lli exits 0');
    is($meta->{emitted_for_every_construct}, 1, 'emitted_for_every_construct=1');
    ok(!defined $meta->{libperl_leak},
        'no libperl_leak flag on clean .ll')
        or diag("libperl_leak: $meta->{libperl_leak}");
};

# Test 2: a .ll that contains a libperl symbol must FAIL its GREEN verdict.
# Mechanism: override LLVMDriver::run to simulate lowering that succeeds and
# lli accepts the output, but the .ll text contains a libperl reference.
# The central guard in MdtestCorpus._run_l_verdict_check must catch this and
# reclassify or add a fail_reason.
subtest 'GREEN .ll with libperl symbol fails the guard' => sub {
    no warnings 'redefine';
    local *Chalk::CodeGen::Harness::LLVMDriver::run = sub {
        my ($class, $return_node, $opts) = @_;
        # Simulate: lowering succeeded, lli accepted the output (exit 0),
        # but the .ll contains a libperl symbol (Perl_sv_2mortal).
        my $L = Chalk::CodeGen::Harness::BehaviorRecord->new(
            return_values     => ['Int:42'],
            wantarray_context => 'scalar',
            stdout            => '',
            stderr            => '',
            exception         => undef,
            object_state      => {},
        );
        my $meta = {
            emitted_for_every_construct => 1,
            marked_unsupported          => 0,
            ll_text                     => 'define i64 @main() { call void @Perl_sv_2mortal() ret i64 42 }',
            runtime_free_fraction       => 1.0,
            lli_exit                    => 0,
        };
        return ($L, $meta);
    };

    my $case = {
        title        => 'synthetic-libperl-leak-test',
        source       => 'do { 42 }',
        behavior     => "return: Int:42\ncontext: scalar\n",
        ir           => "%c = Constant(42) :Int\nreturn %c\nL: GREEN\n",
        source_pos   => undef,
        behavior_pos => undef,
        ir_pos       => undef,
        _perl_actual => 'Int:42',
    };

    my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

    # After G.2: the case must FAIL because the .ll contains a libperl symbol.
    # Before G.2: it would PASS (no central guard).
    isnt($result->{overall}, 'PASS',
        'GREEN case with libperl symbol in .ll must NOT be PASS')
        or diag("fail_reasons: " . join('; ', @{$result->{fail_reasons}}));

    my $has_libperl_reason = grep { /libperl/i } @{$result->{fail_reasons}};
    ok($has_libperl_reason,
        'fail_reasons must mention libperl violation')
        or diag("fail_reasons: " . join('; ', @{$result->{fail_reasons}}));
};

done_testing();
