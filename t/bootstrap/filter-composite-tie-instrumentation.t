# ABOUTME: Tests tie instrumentation in FilterComposite._filter_compare.
# ABOUTME: Verifies CHALK_COUNT_FILTER_TIES env var enables/disables tie recording.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Context;

# Build a minimal two-semiring composite that guarantees a tie.
# Both semirings are the same Boolean instance (or two with identical add behavior)
# pointing to the same slot. We construct two distinct Context values with
# different slot values that add() to a two-element result (both survive) —
# that is the definition of a tie in _filter_compare.
#
# The simplest approach: use a synthetic semiring whose add() returns both
# values (multi-element result), which _filter_compare treats as "no preference".

package TieSemiring {
    use 5.42.0;
    use utf8;
    no warnings 'experimental::class';
    use experimental 'class';

    class TieSemiring {
        field $slot_name_val :param;

        method slot_name() { return $slot_name_val }

        # zero() and one() are required by FilterComposite contract
        method zero() { return Chalk::Bootstrap::Context->new(
            focus => 0, children => [], position => 0, is_zero => true
        ) }
        method one()  { return Chalk::Bootstrap::Context->new(
            focus => 1, children => [], position => 0, is_zero => false
        ) }
        method is_zero($v) { return !defined($v) }

        # multiply: just return right (pass-through for annotation semirings)
        method multiply($l, $r) { return $r }

        # add: return BOTH values — this produces a multi-element result
        # which _filter_compare classifies as "no preference" (a tie).
        method add($l, $r) { return [$l, $r] }
    }
}

# ============================================================
# Test 1: With CHALK_COUNT_FILTER_TIES unset, behavior is unchanged.
# Tie instrumentation must not affect parse results when env var is absent.
# ============================================================
{
    local $ENV{CHALK_COUNT_FILTER_TIES} = undef;
    delete $ENV{CHALK_COUNT_FILTER_TIES};

    my $tie_sr = TieSemiring->new(slot_name_val => 'tie_slot');

    # Build a minimal SA-like final semiring (just needs to respond to is_zero/multiply/add)
    my $sa_sr = TieSemiring->new(slot_name_val => '__sa__');

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$tie_sr, $sa_sr],
    );

    # _filter_compare needs two Context values with different slot annotations
    my $left = Chalk::Bootstrap::Context->new(
        focus => 'left', children => [], position => 0, is_zero => false,
        annotations => { tie_slot => 42 },
    );
    my $right = Chalk::Bootstrap::Context->new(
        focus => 'right', children => [], position => 0, is_zero => false,
        annotations => { tie_slot => 99 },
    );

    my $verdict = $comp->_filter_compare($left, $right);
    is($verdict, 'neither', 'Without env var: tie returns neither (behavior unchanged)');

    # No tie counter should exist
    ok(!$comp->can('tie_count'), 'Without env var: no tie_count method exists')
        if !$ENV{CHALK_COUNT_FILTER_TIES};
}

# ============================================================
# Test 2: With CHALK_COUNT_FILTER_TIES set, ties are recorded.
# ============================================================
{
    local $ENV{CHALK_COUNT_FILTER_TIES} = '1';

    my $tie_sr = TieSemiring->new(slot_name_val => 'tie_slot');
    my $sa_sr  = TieSemiring->new(slot_name_val => '__sa__');

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$tie_sr, $sa_sr],
    );

    # Flush any pre-existing tie log before testing
    $comp->flush_tie_log();

    my $left = Chalk::Bootstrap::Context->new(
        focus => 'left', children => [], position => 0, is_zero => false,
        annotations => { tie_slot => 42 },
    );
    my $right = Chalk::Bootstrap::Context->new(
        focus => 'right', children => [], position => 0, is_zero => false,
        annotations => { tie_slot => 99 },
    );

    my $verdict = $comp->_filter_compare($left, $right);
    is($verdict, 'neither', 'With env var: tie still returns neither (result unchanged)');

    my $log = $comp->tie_log();
    ok(defined($log), 'With env var: tie_log() returns a value');
    is(ref($log), 'ARRAY', 'With env var: tie_log() is an arrayref');
    ok(scalar($log->@*) > 0, 'With env var: at least one tie recorded');

    my $entry = $log->[0];
    ok(defined($entry->{semiring}), 'Tie entry has semiring field');
    ok(defined($entry->{slot}),     'Tie entry has slot field');
    is($entry->{slot}, 'tie_slot',  'Tie entry records the tying slot name');
}

# ============================================================
# Test 3: flush_tie_log() resets the log (enables per-parse attribution).
# ============================================================
{
    local $ENV{CHALK_COUNT_FILTER_TIES} = '1';

    my $tie_sr = TieSemiring->new(slot_name_val => 'tie_slot');
    my $sa_sr  = TieSemiring->new(slot_name_val => '__sa__');

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$tie_sr, $sa_sr],
    );

    $comp->flush_tie_log();

    my $left = Chalk::Bootstrap::Context->new(
        focus => 'left', children => [], position => 0, is_zero => false,
        annotations => { tie_slot => 1 },
    );
    my $right = Chalk::Bootstrap::Context->new(
        focus => 'right', children => [], position => 0, is_zero => false,
        annotations => { tie_slot => 2 },
    );

    $comp->_filter_compare($left, $right);
    my $before = scalar($comp->tie_log()->@*);
    ok($before > 0, 'Tie recorded before flush');

    $comp->flush_tie_log();
    my $after = scalar($comp->tie_log()->@*);
    is($after, 0, 'flush_tie_log() resets log to empty');
}

# ============================================================
# Test 4: A non-tying comparison produces no tie entry.
# ============================================================
{
    local $ENV{CHALK_COUNT_FILTER_TIES} = '1';

    # A semiring whose add() always returns just the left value (clear preference)
    package PreferenceSemiring {
        use 5.42.0;
        use utf8;
        no warnings 'experimental::class';
        use experimental 'class';

        class PreferenceSemiring {
            field $slot_name_val :param;
            method slot_name() { return $slot_name_val }
            method zero() { return Chalk::Bootstrap::Context->new(
                focus => 0, children => [], position => 0, is_zero => true
            ) }
            method one() { return Chalk::Bootstrap::Context->new(
                focus => 1, children => [], position => 0, is_zero => false
            ) }
            method is_zero($v) { return !defined($v) }
            method multiply($l, $r) { return $r }
            # Always picks left — clear preference, no tie
            method add($l, $r) { return $l }
        }
    }

    my $pref_sr = PreferenceSemiring->new(slot_name_val => 'pref_slot');
    my $sa_sr   = TieSemiring->new(slot_name_val => '__sa__');

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$pref_sr, $sa_sr],
    );

    $comp->flush_tie_log();

    my $left = Chalk::Bootstrap::Context->new(
        focus => 'left', children => [], position => 0, is_zero => false,
        annotations => { pref_slot => 10 },
    );
    my $right = Chalk::Bootstrap::Context->new(
        focus => 'right', children => [], position => 0, is_zero => false,
        annotations => { pref_slot => 20 },
    );

    my $verdict = $comp->_filter_compare($left, $right);
    is($verdict, 'right_loses', 'Preference semiring picks left (right_loses)');

    my $log = $comp->tie_log();
    is(scalar($log->@*), 0, 'No tie recorded when semiring expresses clear preference');
}

done_testing();
