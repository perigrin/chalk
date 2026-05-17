# ABOUTME: Tests CHALK_AUDIT_FILTER instrumentation in FilterComposite._filter_compare.
# ABOUTME: Verifies audit_log records per-merge verdicts with no behavior change.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Context;

# ============================================================
# Synthetic semiring helpers
# ============================================================

package LeftSemiring {
    # A semiring whose add() always returns $left — mimics Boolean/Structural
    # convention of returning $left when they have no real opinion.
    use 5.42.0;
    use utf8;
    no warnings 'experimental::class';
    use experimental 'class';

    class LeftSemiring {
        field $slot_name_val :param;
        method slot_name() { return $slot_name_val }
        method zero()      { return Chalk::Bootstrap::Context->new(
            focus => 0, children => [], position => 0, is_zero => true
        ) }
        method one()       { return Chalk::Bootstrap::Context->new(
            focus => 1, children => [], position => 0, is_zero => false
        ) }
        method is_zero($v) { return !defined($v) }
        method multiply($l, $r) { return $r }
        # Returns $l directly — matches Boolean/Structural convention
        method add($l, $r)  { return $l }
    }
}

package RightSemiring {
    # A semiring whose add() always returns $right — expresses a "right wins" opinion.
    use 5.42.0;
    use utf8;
    no warnings 'experimental::class';
    use experimental 'class';

    class RightSemiring {
        field $slot_name_val :param;
        method slot_name() { return $slot_name_val }
        method zero()      { return Chalk::Bootstrap::Context->new(
            focus => 0, children => [], position => 0, is_zero => true
        ) }
        method one()       { return Chalk::Bootstrap::Context->new(
            focus => 1, children => [], position => 0, is_zero => false
        ) }
        method is_zero($v) { return !defined($v) }
        method multiply($l, $r) { return $r }
        # Returns $r directly — expresses a "right wins" opinion
        method add($l, $r)  { return $r }
    }
}

package SASemiring {
    # Minimal SA-like final semiring (last position, no slot_name exposed to FC)
    use 5.42.0;
    use utf8;
    no warnings 'experimental::class';
    use experimental 'class';

    class SASemiring {
        # No slot_name — this is the last semiring, treated as SA by FilterComposite
        method zero()      { return Chalk::Bootstrap::Context->new(
            focus => 0, children => [], position => 0, is_zero => true
        ) }
        method one()       { return Chalk::Bootstrap::Context->new(
            focus => 1, children => [], position => 0, is_zero => false
        ) }
        method is_zero($v) { return !defined($v) }
        method multiply($l, $r) { return $r }
        method add($l, $r)  { return [$l, $r] }
        method annotations() { return {} }
    }
}

# Helper: build two Contexts with distinct annotation slot values
my sub make_ctx($focus_val, %annotations) {
    return Chalk::Bootstrap::Context->new(
        focus       => $focus_val,
        children    => [],
        position    => 0,
        is_zero     => false,
        annotations => \%annotations,
    );
}

# ============================================================
# Test 1: Default behavior unchanged (no env var)
# With no CHALK_AUDIT_FILTER set, audit_log must not be populated
# and the return value must match the existing first-wins logic.
# ============================================================
subtest 'default behavior unchanged without env var' => sub {
    local %ENV = %ENV;
    delete $ENV{CHALK_AUDIT_FILTER};

    # LeftSemiring returns $left — first-wins reads this as "right_loses"
    my $left_sr = LeftSemiring->new(slot_name_val => 'left_slot');
    my $sa_sr   = SASemiring->new();

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$left_sr, $sa_sr],
    );

    my $left  = make_ctx('L', left_slot => 10);
    my $right = make_ctx('R', left_slot => 20);

    my $verdict = $comp->_filter_compare($left, $right);

    # First-wins sees LeftSemiring return $left (==10) which matches $li — right_loses
    is($verdict, 'right_loses', 'default: first-wins behavior preserved');

    # audit_log should be empty / not populated when env var absent
    my $log = $comp->audit_log();
    is(ref($log), 'ARRAY', 'audit_log() returns arrayref');
    is(scalar($log->@*), 0, 'audit_log empty when CHALK_AUDIT_FILTER not set');
};

# ============================================================
# Test 2: With CHALK_AUDIT_FILTER=1, audit_log is populated
# ============================================================
subtest 'audit_log populated with CHALK_AUDIT_FILTER=1' => sub {
    local $ENV{CHALK_AUDIT_FILTER} = '1';

    my $left_sr = LeftSemiring->new(slot_name_val => 'left_slot');
    my $sa_sr   = SASemiring->new();

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$left_sr, $sa_sr],
    );

    $comp->flush_audit_log();

    my $left  = make_ctx('L', left_slot => 10);
    my $right = make_ctx('R', left_slot => 20);

    my $verdict = $comp->_filter_compare($left, $right);

    # Return value must be unchanged
    is($verdict, 'right_loses', 'with CHALK_AUDIT_FILTER: first-wins result preserved');

    my $log = $comp->audit_log();
    is(ref($log), 'ARRAY', 'audit_log() is arrayref');
    ok(scalar($log->@*) > 0, 'audit_log has at least one entry');

    my $entry = $log->[0];
    ok(defined $entry->{verdict_first_wins}, 'entry has verdict_first_wins');
    ok(defined $entry->{verdict_product},    'entry has verdict_product');
    ok(defined $entry->{per_component},      'entry has per_component');
    is(ref($entry->{per_component}), 'ARRAY', 'per_component is arrayref');

    is($entry->{verdict_first_wins}, 'right_loses', 'first_wins recorded correctly');
};

# ============================================================
# Test 3: flush_audit_log() empties the log
# ============================================================
subtest 'flush_audit_log resets log' => sub {
    local $ENV{CHALK_AUDIT_FILTER} = '1';

    my $left_sr = LeftSemiring->new(slot_name_val => 'left_slot');
    my $sa_sr   = SASemiring->new();

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$left_sr, $sa_sr],
    );

    $comp->flush_audit_log();

    my $left  = make_ctx('L', left_slot => 5);
    my $right = make_ctx('R', left_slot => 9);

    $comp->_filter_compare($left, $right);

    ok(scalar($comp->audit_log()->@*) > 0, 'log has entries before flush');

    $comp->flush_audit_log();
    is(scalar($comp->audit_log()->@*), 0, 'flush_audit_log() empties the log');
};

# ============================================================
# Test 4: per_component records slot, verdict for each annotation semiring
# ============================================================
subtest 'per_component records slot and verdict per semiring' => sub {
    local $ENV{CHALK_AUDIT_FILTER} = '1';

    # Two annotation semirings: one returns $left (abstain/left), one returns $right
    my $left_sr  = LeftSemiring->new(slot_name_val  => 'slot_a');
    my $right_sr = RightSemiring->new(slot_name_val => 'slot_b');
    my $sa_sr    = SASemiring->new();

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$left_sr, $right_sr, $sa_sr],
    );

    $comp->flush_audit_log();

    my $left  = make_ctx('L', slot_a => 1, slot_b => 10);
    my $right = make_ctx('R', slot_a => 2, slot_b => 20);

    $comp->_filter_compare($left, $right);

    my $log   = $comp->audit_log();
    my $entry = $log->[0];

    my $pc = $entry->{per_component};
    ok(scalar($pc->@*) >= 1, 'per_component has at least one entry');

    # Each per_component entry should have slot and verdict fields
    for my $c ($pc->@*) {
        ok(defined $c->{slot},    "per_component entry has slot");
        ok(defined $c->{verdict}, "per_component entry has verdict");
    }
};

# ============================================================
# Test 5: audit captures disagreement — verdict_first_wins != verdict_product
# Scenario: LeftSemiring returns $left (first-wins reads as "right_loses")
# but a subsequent RightSemiring returns $right ("left_loses").
# product should detect the conflict and record a different verdict.
# ============================================================
subtest 'audit captures first_wins vs product disagreement' => sub {
    local $ENV{CHALK_AUDIT_FILTER} = '1';

    # LeftSemiring at slot_a returns $l — first-wins terminates here: right_loses
    # RightSemiring at slot_b returns $r — product would also see this
    # When both inputs differ:
    # - first_wins: sees slot_a → $l == $li → right_loses (stops)
    # - product sees slot_a → left, slot_b → right → conflict
    my $left_sr  = LeftSemiring->new(slot_name_val  => 'slot_a');
    my $right_sr = RightSemiring->new(slot_name_val => 'slot_b');
    my $sa_sr    = SASemiring->new();

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$left_sr, $right_sr, $sa_sr],
    );

    $comp->flush_audit_log();

    # slot_a: LeftSemiring returns $l (= li value 1) → product sees 'left'
    # slot_b: RightSemiring returns $r (= ri value 20) → product sees 'right'
    # first-wins: sees slot_a → left wins → terminates as 'right_loses'
    # product: sees left (slot_a) AND right (slot_b) → conflict
    my $left  = make_ctx('L', slot_a => 1, slot_b => 10);
    my $right = make_ctx('R', slot_a => 2, slot_b => 20);

    my $verdict = $comp->_filter_compare($left, $right);

    # First-wins behavior unchanged
    is($verdict, 'right_loses', 'return value is first-wins result (unchanged)');

    my $log = $comp->audit_log();
    ok(scalar($log->@*) > 0, 'audit log has entry for this merge');

    # Find an entry where they disagree
    my @disagreements = grep {
        $_->{verdict_first_wins} ne $_->{verdict_product}
    } $log->@*;

    ok(scalar(@disagreements) > 0,
        'at least one merge where verdict_first_wins != verdict_product');

    my $d = $disagreements[0];
    is($d->{verdict_first_wins}, 'right_loses',
        'disagreement entry: first_wins is right_loses');
    # product sees both slot_a→left and slot_b→right → conflict
    is($d->{verdict_product}, 'conflict',
        'disagreement entry: product detects conflict between components');
};

# ============================================================
# Test 6: audit_log records do NOT contain Context refs
# (per acceptance criterion 4: no memory bloat from Context refs)
# ============================================================
subtest 'audit_log entries do not contain Context refs' => sub {
    local $ENV{CHALK_AUDIT_FILTER} = '1';

    my $left_sr = LeftSemiring->new(slot_name_val => 'slot_a');
    my $sa_sr   = SASemiring->new();

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$left_sr, $sa_sr],
    );

    $comp->flush_audit_log();

    my $left  = make_ctx('L', slot_a => 10);
    my $right = make_ctx('R', slot_a => 20);

    $comp->_filter_compare($left, $right);

    my $log   = $comp->audit_log();
    my $entry = $log->[0];

    # Recursively check no field holds a Context object
    my $has_context_ref;
    $has_context_ref = sub($h) {
        for my $v (values %$h) {
            if (ref($v) && ref($v) eq 'ARRAY') {
                for my $item ($v->@*) {
                    if (ref($item) eq 'HASH') {
                        return true if $has_context_ref->($item);
                    } elsif (ref($item) && ref($item) =~ /Context/) {
                        return true;
                    }
                }
            } elsif (ref($v) && ref($v) =~ /Context/) {
                return true;
            }
        }
        return false;
    };

    ok(!$has_context_ref->($entry),
        'audit_log entry contains no Context refs');
};

# ============================================================
# Test 7: all_abstain verdict when every component has no opinion
# (identity slot values → identity_skip; all return "neither")
# ============================================================
subtest 'all_abstain when all components return same-value slots' => sub {
    local $ENV{CHALK_AUDIT_FILTER} = '1';

    # When both left and right have the SAME slot value, _same_value is true
    # and _filter_compare skips that semiring (identity_skip).
    # After all semirings are skipped, result is 'neither'.
    # product verdict should be 'all_abstain'.
    my $left_sr = LeftSemiring->new(slot_name_val => 'slot_a');
    my $sa_sr   = SASemiring->new();

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$left_sr, $sa_sr],
    );

    $comp->flush_audit_log();

    # Same slot value on both sides → identity skip
    my $shared_val = 42;
    my $left  = make_ctx('L', slot_a => $shared_val);
    my $right = make_ctx('R', slot_a => $shared_val);

    my $verdict = $comp->_filter_compare($left, $right);
    is($verdict, 'neither', 'identity-equal slots → neither (behavior unchanged)');

    my $log = $comp->audit_log();
    ok(scalar($log->@*) > 0, 'audit log has entry even for all-skip');

    my $entry = $log->[0];
    is($entry->{verdict_product}, 'all_abstain',
        'product verdict is all_abstain when every slot is identity-skipped');

    # Per-component entry should record identity_skip
    my $pc = $entry->{per_component};
    my @skipped = grep { $_->{verdict} eq 'identity_skip' } $pc->@*;
    ok(scalar(@skipped) > 0, 'at least one per_component entry records identity_skip');
};

# ============================================================
# Test 8: Real parse — push @arr, $obj->method(); captures disagreement
# This test uses the actual full pipeline to verify the instrumentation
# fires on a known buggy merge and captures at least one disagreement.
# ============================================================
subtest 'real parse captures disagreement on push @arr, $obj->method()' => sub {
    local $ENV{CHALK_AUDIT_FILTER} = '1';

    eval { require TestPipeline; TestPipeline->import(qw(perl_pipeline build_perl_ir_parser)) };
    if ($@) {
        plan skip_all => 'TestPipeline not available';
        return;
    }

    require Chalk::Bootstrap::IR::NodeFactory;
    require Chalk::Bootstrap::BNF::Target::Perl;

    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $raw_ir = TestPipeline::perl_pipeline();
    unless (defined $raw_ir) {
        plan skip_all => 'perl_pipeline returned undef';
        return;
    }

    my $target    = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($raw_ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::AuditTest/g;
    eval $generated;
    if ($@) {
        plan skip_all => "generated grammar failed to eval: $@";
        return;
    }

    my $gen_grammar = Chalk::Grammar::Perl::AuditTest::grammar();

    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = TestPipeline::build_perl_ir_parser($gen_grammar, start => 'Program');

    # Grab the FilterComposite from the parser so we can inspect its audit_log
    my $composite = $parser->semiring();
    unless ($composite->can('audit_log')) {
        plan skip_all => 'parser semiring does not support audit_log';
        return;
    }

    $composite->flush_audit_log();

    my $source = qq{push \@arr, \$obj->method();\n};
    $parser->parse_value($source);

    my $log = $composite->audit_log();
    ok(defined $log, 'audit_log defined after real parse');

    my @disagreements = grep {
        defined $_->{verdict_first_wins}
        && defined $_->{verdict_product}
        && $_->{verdict_first_wins} ne $_->{verdict_product}
    } $log->@*;

    ok(scalar(@disagreements) > 0,
        'real parse of push @arr, $obj->method(); captures at least one first_wins/product disagreement');
};

done_testing();
