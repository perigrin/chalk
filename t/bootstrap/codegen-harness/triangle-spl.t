# ABOUTME: S/P/L triangle tests — three-corner verdict for computation-slice idioms (Phase 3d).
# ABOUTME: Asserts PASS on L-GREEN idioms, matrix cell classification, and F7 same-object guard.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';
use Scalar::Util qw(refaddr);

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Return;

use Chalk::CodeGen::Harness::BehaviorRecord;
use Chalk::CodeGen::Harness::Comparator;
use Chalk::CodeGen::Harness::LLVMDriver;
use Chalk::CodeGen::Harness::ReturnNodePerlDriver;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless ( -x $LLI ) {
    plan skip_all => "lli not found at $LLI";
}

# ---------------------------------------------------------------------------
# Helper: build the arith-add graph (L-GREEN: return 1 + 2)
# ---------------------------------------------------------------------------
sub _build_arith_add {
    my $f  = Chalk::IR::NodeFactory->new;
    my $c1 = $f->make( 'Constant', value => '1', const_type => 'integer' );
    $c1->set_representation('Int');
    my $c2 = $f->make( 'Constant', value => '2', const_type => 'integer' );
    $c2->set_representation('Int');
    my $add = $f->make( 'Add', inputs => [ $c1, $c2 ] );
    $add->set_representation('Int');
    my $ret = $f->make_cfg( 'Return', inputs => [$add] );
    return $ret;
}

# ---------------------------------------------------------------------------
# Helper: build a Scalar-representation graph (L cannot lower)
# ---------------------------------------------------------------------------
sub _build_scalar_graph {
    my $f  = Chalk::IR::NodeFactory->new;
    my $c1 = $f->make( 'Constant', value => '1', const_type => 'integer' );
    $c1->set_representation('Scalar');    # Scalar = GAP on L corner
    my $ret = $f->make_cfg( 'Return', inputs => [$c1] );
    return $ret;
}

# ---------------------------------------------------------------------------
# SECTION 1 — LLVMDriver basics
# ---------------------------------------------------------------------------

subtest 'LLVMDriver returns a BehaviorRecord for an L-GREEN graph' => sub {
    my $graph = _build_arith_add();

    my ( $L, $l_meta ) = Chalk::CodeGen::Harness::LLVMDriver->run($graph);

    isa_ok( $L, 'Chalk::CodeGen::Harness::BehaviorRecord',
        'LLVMDriver->run returns a BehaviorRecord' );
    ok( defined $l_meta, 'LLVMDriver->run returns emission meta hashref' );
    ok( $l_meta->{emitted_for_every_construct}, 'L-GREEN graph: emitted_for_every_construct is true' );
    ok( !$l_meta->{marked_unsupported},          'L-GREEN graph: not marked_unsupported' );
};

subtest 'LLVMDriver BehaviorRecord has correct return value for arith-add' => sub {
    my $graph = _build_arith_add();
    my ( $L, $l_meta ) = Chalk::CodeGen::Harness::LLVMDriver->run($graph);

    my $rv = $L->return_values;
    is( scalar(@$rv), 1,   'return_values has one element' );
    is( $rv->[0], '3',     'return_values[0] is "3" (1+2)' );
};

subtest 'LLVMDriver L record is libperl-free (no Perl_/SV_ in .ll)' => sub {
    my $graph = _build_arith_add();
    my ( $L, $l_meta ) = Chalk::CodeGen::Harness::LLVMDriver->run($graph);

    # The emission meta must carry the ll_text so we can inspect it.
    my $ll_text = $l_meta->{ll_text};
    ok( defined $ll_text, 'emission_meta carries ll_text for inspection' );
    unlike( $ll_text, qr/Perl_|SV_|libperl/,
        'generated .ll contains no Perl_/SV_/libperl symbols (libperl-free)' );
};

subtest 'LLVMDriver L record carries runtime-free coverage fraction' => sub {
    my $graph = _build_arith_add();
    my ( $L, $l_meta ) = Chalk::CodeGen::Harness::LLVMDriver->run($graph);

    ok( exists $l_meta->{runtime_free_fraction}, 'emission_meta carries runtime_free_fraction' );
    my $frac = $l_meta->{runtime_free_fraction};
    ok( defined $frac, 'runtime_free_fraction is defined' );
    ok( $frac >= 0 && $frac <= 1, 'runtime_free_fraction is in [0,1]' );
    is( $frac, 1.0, 'arith-add is fully runtime-free (fraction == 1.0)' );
};

subtest 'LLVMDriver returns GAP for Scalar-representation graph' => sub {
    my $graph = _build_scalar_graph();
    my ( $L, $l_meta ) = Chalk::CodeGen::Harness::LLVMDriver->run($graph);

    ok( $l_meta->{marked_unsupported} || !$l_meta->{emitted_for_every_construct},
        'Scalar-repr graph verdicts as cannot-lower (GAP, not a libperl fallback)' );
    is( $l_meta->{gap_reason}, 'cannot-lower-runtime-free',
        'gap_reason is cannot-lower-runtime-free' );
};

# ---------------------------------------------------------------------------
# SECTION 2 — Three-corner Comparator (S/P/L triangle)
# ---------------------------------------------------------------------------

# Helper: make a BehaviorRecord with a single return_value
sub _rec {
    my ($val) = @_;
    return Chalk::CodeGen::Harness::BehaviorRecord->new( return_values => [$val] );
}

subtest 'three-corner verdict: all agree - PASS' => sub {
    my $S = _rec('3');
    my $P = _rec('3');
    my $L = _rec('3');

    my $result = Chalk::CodeGen::Harness::Comparator->verdict_spl(
        $S, $P, $L,
        { emitted_for_every_construct => 1, marked_unsupported => 0 },
        { emitted_for_every_construct => 1, marked_unsupported => 0, runtime_free_fraction => 1.0 },
    );

    is( $result->{verdict}, 'PASS', 'S=P=L -> PASS' );
};

subtest 'three-corner verdict: P=L!=S - upstream IR bug' => sub {
    my $S = _rec('99');    # oracle says 99
    my $P = _rec('3');     # Perl codegen says 3
    my $L = _rec('3');     # LLVM says 3 too — they agree, differ from oracle

    my $result = Chalk::CodeGen::Harness::Comparator->verdict_spl(
        $S, $P, $L,
        { emitted_for_every_construct => 1, marked_unsupported => 0 },
        { emitted_for_every_construct => 1, marked_unsupported => 0, runtime_free_fraction => 1.0 },
    );

    is( $result->{verdict}, 'MISCOMPILE', 'P=L!=S -> MISCOMPILE' );
    is( $result->{implicated_layer}, 'upstream-ir',
        'P=L!=S implicates upstream-ir (both lowerings agree vs. oracle)' );
};

subtest 'three-corner verdict: P!=L - codegen divergence, not auto-blame-IR' => sub {
    my $S = _rec('3');     # oracle says 3
    my $P = _rec('3');     # Perl codegen says 3 (agrees with oracle)
    my $L = _rec('99');    # LLVM says 99 (diverges)

    my $result = Chalk::CodeGen::Harness::Comparator->verdict_spl(
        $S, $P, $L,
        { emitted_for_every_construct => 1, marked_unsupported => 0 },
        { emitted_for_every_construct => 1, marked_unsupported => 0, runtime_free_fraction => 1.0 },
    );

    is( $result->{verdict}, 'MISCOMPILE', 'P!=L -> MISCOMPILE' );
    is( $result->{implicated_layer}, 'codegen-divergence',
        'P!=L implicates codegen-divergence (not upstream-ir)' );
};

subtest 'three-corner verdict: L cannot lower - underspecified-ir GAP (distinct from MISCOMPILE)' => sub {
    my $S = _rec('3');
    my $P = _rec('3');

    # L-cannot-lower: marked_unsupported=true (or emitted_for_every_construct=false)
    my $L_gap = Chalk::CodeGen::Harness::BehaviorRecord->new( return_values => [] );

    my $result = Chalk::CodeGen::Harness::Comparator->verdict_spl(
        $S, $P, $L_gap,
        { emitted_for_every_construct => 1, marked_unsupported => 0 },
        { emitted_for_every_construct => 0, marked_unsupported => 1, gap_reason => 'cannot-lower-runtime-free' },
    );

    is( $result->{verdict}, 'GAP', 'L-cannot-lower -> GAP (not MISCOMPILE, not PASS)' );
    is( $result->{implicated_layer}, 'underspecified-ir',
        'L-cannot-lower implicates underspecified-ir' );
};

subtest 'P=L!=S not laundered: verdict is upstream-ir, never "both codegens pass"' => sub {
    # Regression guard: ensure the comparator does NOT produce PASS when P=L but both
    # diverge from S. The correct verdict is MISCOMPILE/upstream-ir.
    my $S = _rec('42');
    my $P = _rec('0');
    my $L = _rec('0');

    my $result = Chalk::CodeGen::Harness::Comparator->verdict_spl(
        $S, $P, $L,
        { emitted_for_every_construct => 1, marked_unsupported => 0 },
        { emitted_for_every_construct => 1, marked_unsupported => 0, runtime_free_fraction => 1.0 },
    );

    isnt( $result->{verdict}, 'PASS', 'P=L!=S is NOT laundered as PASS' );
    is( $result->{verdict}, 'MISCOMPILE', 'P=L!=S -> MISCOMPILE' );
    is( $result->{implicated_layer}, 'upstream-ir', 'implicates upstream-ir' );
};

subtest 'mostly-Scalar L is not a valid agreement (coverage guard)' => sub {
    # A triangle PASS requires L to be fully runtime-free.
    # P=L on a mostly-Scalar L (runtime_free_fraction < 1.0) is not a valid PASS.
    my $S = _rec('3');
    my $P = _rec('3');
    my $L = _rec('3');    # values agree, but L used Scalar fallback

    my $result = Chalk::CodeGen::Harness::Comparator->verdict_spl(
        $S, $P, $L,
        { emitted_for_every_construct => 1, marked_unsupported => 0 },
        {   emitted_for_every_construct => 1,
            marked_unsupported          => 0,
            runtime_free_fraction       => 0.5,    # only 50% runtime-free
        },
    );

    isnt( $result->{verdict}, 'PASS',
        'P=L with runtime_free_fraction<1.0 is NOT a valid PASS (coverage guard)' );
    is( $result->{verdict}, 'GAP', 'mostly-Scalar L -> GAP (not PASS)' );
    like( $result->{reason} // '', qr/coverage|runtime.free/i,
        'GAP reason mentions coverage / runtime-free' );
};

# ---------------------------------------------------------------------------
# SECTION 3 — F7 guard: all corners must receive the IDENTICAL graph object
# ---------------------------------------------------------------------------

subtest 'F7 guard: separately-built graphs to different corners FAILS' => sub {
    # Two graphs built from the same content — but different objects.
    my $graph_for_P = _build_arith_add();
    my $graph_for_L = _build_arith_add();

    # Sanity: they are different objects
    isnt( refaddr($graph_for_P), refaddr($graph_for_L),
        'two separately-built graphs are different objects (test precondition)' );

    # The F7 check lives in the triangle rig (or a standalone guard function).
    # It must die/croak/return an error when the two graphs are different objects.
    my $caught = eval {
        Chalk::CodeGen::Harness::Comparator->check_f7( $graph_for_P, $graph_for_L );
        0;    # no exception = guard did NOT fire
    };
    if ($@) {
        $caught = 1;
    }

    ok( $caught, 'F7 guard fires when P and L corners receive different graph objects' );
};

subtest 'F7 guard: same graph object passes' => sub {
    my $graph = _build_arith_add();

    # Same object for both corners — F7 must NOT fire.
    my $caught = eval {
        Chalk::CodeGen::Harness::Comparator->check_f7( $graph, $graph );
        0;
    };
    if ($@) {
        $caught = 1;
    }

    ok( !$caught, 'F7 guard does NOT fire when P and L corners receive the same graph object' );
};

# ---------------------------------------------------------------------------
# SECTION 4 — REAL S/P/L triangle PASS for arith-add (the load-bearing proof)
# ---------------------------------------------------------------------------

subtest 'real S/P/L triangle PASS for arith-add' => sub {
    # Build ONE graph object (F7: same object for both non-oracle corners).
    my $graph = _build_arith_add();

    # S: perl oracle — run "return 1 + 2" under perl and capture the result.
    # For the triangle test, we build S directly as a BehaviorRecord with
    # the known perl oracle output "3". (The full PerlDriver/RunUnderPerl path
    # is tested elsewhere; here we focus on the triangle verdict.)
    my $S = Chalk::CodeGen::Harness::BehaviorRecord->new( return_values => ['3'] );

    # P: Perl codegen corner — lower the SAME typed graph to Perl, run under perl.
    my ( $P, $p_meta ) = Chalk::CodeGen::Harness::ReturnNodePerlDriver->run(
        $graph,
        { context => 'scalar' },
    );

    # L: LLVM corner — lower the SAME graph to LLVM IR, run via lli.
    my ( $L, $l_meta ) = Chalk::CodeGen::Harness::LLVMDriver->run($graph);

    # F7 check: graph identity for P and L corners.
    eval { Chalk::CodeGen::Harness::Comparator->check_f7( $graph, $graph ) };
    ok( !$@, 'F7: same graph object for P and L corners' );

    # Show the actual values (diagnostic).
    my $s_val = $S->return_values->[0] // '(undef)';
    my $p_val = ( $P && @{ $P->return_values } ) ? $P->return_values->[0] : '(undef)';
    my $l_val = ( $L && @{ $L->return_values } ) ? $L->return_values->[0] : '(undef)';
    diag("S (perl oracle):  $s_val");
    diag("P (Perl codegen): $p_val");
    diag("L (LLVM/lli):     $l_val");
    diag( "L runtime_free_fraction: " . ( $l_meta->{runtime_free_fraction} // '(undef)' ) );

    # L must be libperl-free.
    my $ll_text = $l_meta->{ll_text} // '';
    unlike( $ll_text, qr/Perl_|SV_|libperl/,
        'L corner: generated .ll is libperl-free' );

    # L must be fully runtime-free.
    my $frac = $l_meta->{runtime_free_fraction} // 0;
    is( $frac, 1.0, 'L corner: fully runtime-free (fraction == 1.0)' );

    # Three-corner verdict.
    my $result = Chalk::CodeGen::Harness::Comparator->verdict_spl(
        $S, $P, $L, $p_meta, $l_meta,
    );

    diag( "Three-corner verdict: " . $result->{verdict} );
    is( $result->{verdict}, 'PASS', 'arith-add S/P/L triangle verdict is PASS' );
};

done_testing;
