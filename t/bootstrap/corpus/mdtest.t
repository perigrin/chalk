# ABOUTME: End-to-end runner for the mdtest-style typed-IR corpus (Step A+B).
# ABOUTME: Parses arithmetic.md, asserts behavior+ir-shape+L-verdict for each case; includes guards.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';
use File::Temp qw(tempfile);
use File::Copy qw(copy);

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Modulo;
use Chalk::IR::Node::Coerce;
use Chalk::IR::Node::Return;
use Chalk::IR::Target::LLVM;

use Chalk::CodeGen::Harness::MdtestCorpus;
use Chalk::CodeGen::Harness::LLVMDriver;
use Chalk::CodeGen::Harness::BehaviorRecord;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

my $ARITHMETIC_MD = 't/corpus/mdtest/arithmetic.md';

unless (-f $ARITHMETIC_MD) {
    plan skip_all => "arithmetic.md not found at $ARITHMETIC_MD";
}

# ---------------------------------------------------------------------------
# Helper: build the exact typed Return nodes that the LLVMGapMap uses
# for each arith-* tag.  Returns undef for unknown tags (GAP idioms).
# ---------------------------------------------------------------------------

sub _int_const {
    my ($f, $val) = @_;
    my $c = $f->make('Constant', value => "$val", const_type => 'integer');
    $c->set_representation('Int');
    return $c;
}

sub _build_arith_graph {
    my ($tag) = @_;

    if ($tag eq 'arith-add') {
        my $f   = Chalk::IR::NodeFactory->new;
        my $c1  = _int_const($f, 1);
        my $c2  = _int_const($f, 2);
        my $add = $f->make('Add', inputs => [$c1, $c2]);
        $add->set_representation('Int');
        return $f->make_cfg('Return', inputs => [$add]);
    }
    if ($tag eq 'arith-sub') {
        my $f   = Chalk::IR::NodeFactory->new;
        my $c5  = _int_const($f, 5);
        my $c3  = _int_const($f, 3);
        my $sub = $f->make('Subtract', inputs => [$c5, $c3]);
        $sub->set_representation('Int');
        return $f->make_cfg('Return', inputs => [$sub]);
    }
    if ($tag eq 'arith-mul') {
        my $f   = Chalk::IR::NodeFactory->new;
        my $c3  = _int_const($f, 3);
        my $c4  = _int_const($f, 4);
        my $mul = $f->make('Multiply', inputs => [$c3, $c4]);
        $mul->set_representation('Int');
        return $f->make_cfg('Return', inputs => [$mul]);
    }
    if ($tag eq 'arith-div') {
        my $f    = Chalk::IR::NodeFactory->new;
        my $c3   = _int_const($f, 3);
        my $c4   = _int_const($f, 4);
        my $coe3 = $f->make('Coerce', inputs => [$c3], from_repr => 'Int', to_repr => 'Num');
        $coe3->set_representation('Num');
        my $coe4 = $f->make('Coerce', inputs => [$c4], from_repr => 'Int', to_repr => 'Num');
        $coe4->set_representation('Num');
        my $div  = $f->make('Divide', inputs => [$coe3, $coe4]);
        $div->set_representation('Num');
        return $f->make_cfg('Return', inputs => [$div]);
    }
    if ($tag eq 'arith-mod') {
        my $f   = Chalk::IR::NodeFactory->new;
        my $c7  = _int_const($f, -7);
        my $c3  = _int_const($f, 3);
        my $mod = $f->make('Modulo', inputs => [$c7, $c3]);
        $mod->set_representation('Int');
        return $f->make_cfg('Return', inputs => [$mod]);
    }
    return undef;
}

# perl oracle values for the arith-* idioms (matches perl behavior):
my %PERL_ORACLE = (
    'arith-add' => '3',
    'arith-sub' => '2',
    'arith-mul' => '12',
    'arith-div' => '0.75',
    'arith-mod' => '2',
);

my $graph_for = sub { _build_arith_graph($_[0]) };
my $oracle_for = sub { $PERL_ORACLE{$_[0]} };

# ---------------------------------------------------------------------------
# SECTION 1: Parse arithmetic.md and run all 5 cases end-to-end
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($ARITHMETIC_MD);
is(scalar(@$cases), 5, 'arithmetic.md has 5 cases');

my @case_titles = map { $_->{title} } @$cases;
ok((grep { /Integer addition/ } @case_titles), 'case: Integer addition present');
ok((grep { /Integer subtraction/ } @case_titles), 'case: Integer subtraction present');
ok((grep { /Integer multiplication/ } @case_titles), 'case: Integer multiplication present');
ok((grep { /Float division/ } @case_titles), 'case: Float division present');
ok((grep { /Integer modulo/ } @case_titles), 'case: Integer modulo right-sign present');

# Run all 5 cases
for my $case (@$cases) {
    my $title = $case->{title};

    subtest "case: $title" => sub {
        my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {
            graph_for      => $graph_for,
            perl_oracle_for => $oracle_for,
        });

        # Behavior check
        is($result->{behavior}{verdict}, 'PASS',
            "$title: behavior oracle matches")
            or diag("  behavior fail: " . join('; ', @{ $result->{fail_reasons} }));

        # IR-shape check
        isnt($result->{ir_shape}{verdict}, 'FAIL',
            "$title: ir-shape not FAIL")
            or diag("  ir-shape missing: " . join(', ', @{ $result->{ir_shape}{missing} // [] }));

        # L-verdict check
        is($result->{l_verdict}{verdict}, 'PASS',
            "$title: L verdict matches")
            or diag("  L fail: " . join('; ', @{ $result->{fail_reasons} }));

        # Overall
        is($result->{overall}, 'PASS', "$title: overall PASS")
            or diag("  fail reasons: " . join('; ', @{ $result->{fail_reasons} }));

        # For GREEN cases: assert lli output agrees with perl oracle
        if (($result->{l_verdict}{declared} // '') eq 'GREEN') {
            my $return_node = $graph_for->( _extract_ir_tag_from_case($case) );
            if (defined $return_node) {
                my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
                ok(!$meta->{marked_unsupported}, "$title: L is truly GREEN (not marked_unsupported)");
                my $lli_out = $L->return_values->[0] // '';
                my $tag     = _extract_ir_tag_from_case($case) // '';
                my $oracle  = $PERL_ORACLE{$tag} // '';
                if (length $oracle) {
                    if ($lli_out =~ /\./ || $oracle =~ /\./) {
                        ok(abs($lli_out - $oracle) < 1e-9,
                            "$title: lli output '$lli_out' == perl oracle '$oracle'");
                    } else {
                        is($lli_out, $oracle, "$title: lli output == perl oracle");
                    }
                }
            }
        }
    };
}

# ---------------------------------------------------------------------------
# SECTION 2: Capture mode
#
# Create a scratch .md with an empty behavior block, run in capture mode,
# verify the behavior block gets filled in with the perl oracle value.
# ---------------------------------------------------------------------------

subtest 'capture mode: empty behavior block gets filled from perl oracle' => sub {
    my $scratch_md = <<'END_MD';
# Scratch

## Capture test

```perl
# source
1 + 2
```

```behavior
```

```ir
# ir-tag: arith-add
Constant(1) :Int
Constant(2) :Int
Add(Int, Int) :Int
Return(Add)
L: GREEN
```
END_MD

    my ($fh, $tmpfile) = tempfile(SUFFIX => '.md', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $scratch_md;
    close $fh;

    # Run in capture mode
    my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($tmpfile);
    is(scalar(@$cases), 1, 'scratch md has 1 case');

    my $case = $cases->[0];
    my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {
        graph_for    => $graph_for,
        capture_mode => 1,
        md_path      => $tmpfile,
    });

    is($result->{behavior}{verdict}, 'CAPTURED', 'behavior verdict is CAPTURED');
    is($result->{behavior}{actual}, '3', 'captured value is 3 from perl oracle');
    is($result->{overall}, 'CAPTURED', 'overall verdict is CAPTURED');

    # Re-read the file: the behavior block should now be filled
    open my $rfh, '<:utf8', $tmpfile or die "cannot open $tmpfile: $!";
    my $new_content = do { local $/; <$rfh> };
    close $rfh;

    like($new_content, qr/return: 3/, 'rewritten file contains "return: 3"');
    unlike($new_content, qr/^```behavior\s*```/m, 'behavior block is no longer empty');

    # Run again on the rewritten file — now it should PASS (not CAPTURED)
    my $cases2  = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($tmpfile);
    my $case2   = $cases2->[0];
    my $result2 = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case2, {
        graph_for    => $graph_for,
        capture_mode => 1,   # still on, but block is now non-empty
        md_path      => $tmpfile,
    });

    is($result2->{behavior}{verdict}, 'PASS',
        'after capture: re-running the frozen block gives PASS (not CAPTURED again)');
};

# ---------------------------------------------------------------------------
# SECTION 3: Negative guards — the corpus must not lie
# ---------------------------------------------------------------------------

# GUARD 1: hand-written behavior that disagrees with perl MUST fail
subtest 'guard: hand-written behavior mismatch FAILS' => sub {
    my $bad_md = <<'END_MD';
# Bad

## Bad behavior case

```perl
# source
1 + 2
```

```behavior
return: 99
context: scalar
```

```ir
# ir-tag: arith-add
Constant(1) :Int
Constant(2) :Int
Add(Int, Int) :Int
Return(Add)
L: GREEN
```
END_MD

    my ($fh, $tmpfile) = tempfile(SUFFIX => '.md', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $bad_md;
    close $fh;

    my $cases  = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($tmpfile);
    my $case   = $cases->[0];
    my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {
        graph_for => $graph_for,
    });

    is($result->{behavior}{verdict}, 'FAIL',
        'behavior with wrong return:99 is FAIL (perl says 3)');
    is($result->{overall}, 'FAIL', 'overall is FAIL');
    ok(scalar(@{ $result->{fail_reasons} }) > 0, 'at least one fail reason recorded');
    like($result->{fail_reasons}[0], qr/mismatch|behavior/i,
        'fail reason mentions mismatch or behavior');
};

# GUARD 2: ir-shape declaring a node absent from the real graph MUST fail
subtest 'guard: ir-shape subset dishonesty FAILS' => sub {
    # Declare a Coerce(Int -> Num) node that does NOT exist in the arith-add graph
    # (arith-add is pure Int with no coercion).
    my $bad_ir_md = <<'END_MD';
# Bad IR

## Bad ir shape case

```perl
# source
1 + 2
```

```behavior
return: 3
context: scalar
```

```ir
# ir-tag: arith-add
Constant(1) :Int
Constant(2) :Int
Coerce(Int -> Num)
Add(Int, Int) :Int
Return(Add)
L: GREEN
```
END_MD

    my ($fh, $tmpfile) = tempfile(SUFFIX => '.md', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $bad_ir_md;
    close $fh;

    my $cases  = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($tmpfile);
    my $case   = $cases->[0];
    my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {
        graph_for => $graph_for,
    });

    is($result->{ir_shape}{verdict}, 'FAIL',
        'ir-shape FAILS when declared Coerce node is absent from arith-add graph');
    is($result->{overall}, 'FAIL', 'overall is FAIL');
    ok(scalar(@{ $result->{ir_shape}{missing} }) > 0, 'missing list is non-empty');
    like($result->{ir_shape}{missing}[0], qr/Coerce/,
        'missing entry mentions Coerce');
};

# GUARD 3: claiming L: GREEN for a real GAP idiom MUST fail
subtest 'guard: L verdict GREEN for a real GAP FAILS' => sub {
    # Build a Scalar-repr graph (cannot lower without libperl → real GAP)
    my $scalar_graph_for = sub {
        my ($tag) = @_;
        return undef unless $tag eq 'gap-test';
        my $f = Chalk::IR::NodeFactory->new;
        my $c = $f->make('Constant', value => '1', const_type => 'integer');
        $c->set_representation('Scalar');    # Scalar = GAP on L corner
        return $f->make_cfg('Return', inputs => [$c]);
    };

    my $fake_green_md = <<'END_MD';
# Fake Green

## Fake GREEN verdict case

```perl
# source
1
```

```behavior
return: 1
context: scalar
```

```ir
# ir-tag: gap-test
Constant(1) :Scalar
Return(Constant)
L: GREEN
```
END_MD

    my ($fh, $tmpfile) = tempfile(SUFFIX => '.md', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $fake_green_md;
    close $fh;

    my $cases  = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($tmpfile);
    my $case   = $cases->[0];
    my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {
        graph_for => $scalar_graph_for,
    });

    is($result->{l_verdict}{verdict}, 'FAIL',
        'L verdict FAILS when actual is GAP but declared GREEN');
    is($result->{overall}, 'FAIL', 'overall is FAIL');
    like($result->{fail_reasons}[0] // '', qr/L verdict|GAP|GREEN/i,
        'fail reason mentions L verdict or GAP/GREEN');
};

done_testing;

# ---------------------------------------------------------------------------
# Helper used in SECTION 1 for inlining
# ---------------------------------------------------------------------------

sub _extract_ir_tag_from_case {
    my ($case) = @_;
    my $ir = $case->{ir} // '';
    if ($ir =~ /^\s*#\s*ir-tag:\s*(\S+)/m) {
        return $1;
    }
    return undef;
}
