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

# Test 3: a GREEN .ll that contains libperl-lookalike words only inside a
# string-constant payload must NOT be false-flagged.
# H2: the guard greps the full .ll text including c"..." payload lines.
# A string constant like `c"an SV in a HV\00"` matches \bSV\b and \bHV\b
# even though there is no actual libperl reference — it is a string literal
# that happens to contain "SV"/"HV" as English words. This produces a
# false MISCOMPILE verdict on a genuinely runtime-free GREEN case.
subtest 'GREEN .ll with SV/HV only inside string-constant payload must PASS guard' => sub {
    no warnings 'redefine';
    local *Chalk::CodeGen::Harness::LLVMDriver::run = sub {
        my ($class, $return_node, $opts) = @_;
        # Simulate: lowering succeeded with a string literal "an SV in a HV".
        # The .ll text has the string as a global constant — no actual libperl call.
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
            # The .ll has a string-constant global whose payload contains SV and HV
            # as ordinary English words (not libperl references).
            ll_text => join("\n",
                '@str_const_0 = private unnamed_addr constant [15 x i8] c"an SV in a HV\00", align 1',
                'define i32 @main() {',
                'entry:',
                '  %ptr = getelementptr inbounds [15 x i8], [15 x i8]* @str_const_0, i64 0, i64 0',
                '  %r = call i32 (i8*, ...) @printf(i8* %ptr)',
                '  ret i32 42',
                '}',
                'declare i32 @printf(i8*, ...)',
            ),
            runtime_free_fraction => 1.0,
            lli_exit              => 0,
        };
        return ($L, $meta);
    };

    my $case = {
        title        => 'synthetic-str-const-sv-hv-test',
        source       => 'do { 42 }',
        behavior     => "return: Int:42\ncontext: scalar\n",
        ir           => "%c = Constant(42) :Int\nreturn %c\nL: GREEN\n",
        source_pos   => undef,
        behavior_pos => undef,
        ir_pos       => undef,
        _perl_actual => 'Int:42',
    };

    my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

    # H2 fix: the guard must NOT fire on SV/HV that appear only inside a
    # string-constant payload line. The case must PASS.
    is($result->{overall}, 'PASS',
        'GREEN case with SV/HV only in string-constant payload must PASS (no false libperl flag)')
        or diag("unexpected fail_reasons: " . join('; ', @{$result->{fail_reasons} // []}));

    my $has_false_libperl = defined $result->{fail_reasons}
        && grep { /libperl/i } @{$result->{fail_reasons}};
    ok(!$has_false_libperl,
        'no libperl fail_reason for string-constant SV/HV (H2 false-positive must be gone)')
        or diag("false-positive fail_reasons: " . join('; ', @{$result->{fail_reasons}}));
};

# Test 4: CG2 (R1 reopened) — the strip must only blank the c"..." PAYLOAD substring,
# NOT the whole line. A libperl symbol on a constant-definition line OUTSIDE the payload
# (e.g. in the type annotation or global name) must still be caught after the strip.
#
# Before CG2 fix: `s/^[^\n]*\bconstant\b[^\n]*\bc"[^\n]*$//mg` blanks the ENTIRE line.
# A libperl symbol that appears ONLY in the global name of a constant line (not in the
# payload, and not in any other instruction) is silently swallowed.
# After CG2 fix: only the c"..." payload is removed (`s/\bc"[^"]*"//mg`), so the global
# name is preserved and the Perl_ prefix remains visible to the guard.
subtest 'CG2: libperl global name on constant-only line caught after payload-only strip' => sub {
    no warnings 'redefine';
    local *Chalk::CodeGen::Harness::LLVMDriver::run = sub {
        my ($class, $return_node, $opts) = @_;
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
            # Construct a .ll where:
            # - The constant definition line has "Perl_" in the GLOBAL NAME (not the payload)
            # - NO GEP or other instruction references that global name
            # Before CG2: whole line stripped -> Perl_ swallowed -> guard misses it.
            # After CG2: only c"..." stripped -> Perl_ prefix in name preserved -> caught.
            ll_text => join("\n",
                # @Perl_named = ... constant ... c"harmless payload\00"
                # The global name is a libperl reference. NOT referenced from @main or GEPs.
                'define i32 @main() {',
                'entry:',
                '  ret i32 42',
                '}',
                # This line: Perl_ is in the GLOBAL NAME, not in the c"..." payload.
                # Old strip: whole line removed -> Perl_ invisible.
                # New strip: only c"harmless\00" removed -> @Perl_named still visible.
                '@Perl_named = private unnamed_addr constant [8 x i8] c"harmless\00", align 1',
                'declare i32 @printf(i8*, ...)',
            ),
            runtime_free_fraction => 1.0,
            lli_exit              => 0,
        };
        return ($L, $meta);
    };

    my $case = {
        title        => 'cg2-libperl-in-global-name-of-constant',
        source       => 'do { 42 }',
        behavior     => "return: Int:42\ncontext: scalar\n",
        ir           => "%c = Constant(42) :Int\nreturn %c\nL: GREEN\n",
        source_pos   => undef,
        behavior_pos => undef,
        ir_pos       => undef,
        _perl_actual => 'Int:42',
    };

    my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

    # After CG2: the case MUST FAIL (Perl_ in global name, only on constant line).
    # Before CG2: the whole constant line is stripped -> Perl_ swallowed -> PASS (wrong).
    isnt($result->{overall}, 'PASS',
        'CG2: libperl global name on constant-only line must FAIL (payload-only strip preserves name)')
        or diag("Guard swallowed Perl_ via whole-line strip; fail_reasons: "
                . join('; ', @{$result->{fail_reasons} // []}));

    my $has_libperl_reason = grep { /libperl/i } @{$result->{fail_reasons} // []};
    ok($has_libperl_reason,
        'CG2: fail_reasons mention libperl (name preserved after payload-only strip)')
        or diag("fail_reasons: " . join('; ', @{$result->{fail_reasons} // []}));
};

done_testing();
