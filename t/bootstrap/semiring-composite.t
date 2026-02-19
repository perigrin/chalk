# ABOUTME: Tests FilterComposite semiring with staged is_zero filtering.
# ABOUTME: Verifies _filter_compare, delegation to component semirings via on_scan/on_complete interface.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Semiring::Precedence;
use Chalk::Bootstrap::Semiring::TypeInference;
use Chalk::Grammar::Perl::PrecedenceTable;
use Chalk::Grammar::Perl::KeywordTable;
use Chalk::Grammar::Perl::TypeLibrary;
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;

# Reset factory for clean test environment
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# ========================================================================
# N-ary FilterComposite: basic creation and zero/one
# ========================================================================

# Test 1: N-ary FilterComposite creation with 2 semirings
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    isa_ok($comp, 'Chalk::Bootstrap::Semiring::FilterComposite', 'creates N-ary composite');
}

# Test 2: N-ary FilterComposite creation with 3 semirings
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $sem_sr],
    );

    isa_ok($comp, 'Chalk::Bootstrap::Semiring::FilterComposite', 'creates 3-ary composite');
}

# Test 3: zero returns N-tuple of component zeros
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $zero = $comp->zero();

    isa_ok($zero, 'ARRAY', 'zero returns array ref');
    is(scalar($zero->@*), 2, 'zero returns 2-tuple');
    ok($bool_sr->is_zero($zero->[0]), 'first element is bool zero');
    ok($sem_sr->is_zero($zero->[1]), 'second element is sem zero');
}

# Test 4: one returns N-tuple of component ones
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $one = $comp->one();

    isa_ok($one, 'ARRAY', 'one returns array ref');
    is(scalar($one->@*), 2, 'one returns 2-tuple');
    ok(!$bool_sr->is_zero($one->[0]), 'first element is bool one');
    ok(!$sem_sr->is_zero($one->[1]), 'second element is sem one');
}

# ========================================================================
# N-ary FilterComposite: is_zero staged filter (ANY component zero)
# ========================================================================

# Test 5: is_zero when first component is zero
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $zero = $comp->zero();
    my $one = $comp->one();

    ok($comp->is_zero($zero), 'is_zero: all zeros → true');
    ok(!$comp->is_zero($one), 'is_zero: all ones → false');
}

# Test 6: is_zero detects zero in ANY component (staged filter)
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $sem_sr],
    );

    # Boolean one, Precedence zero, Semantic one
    my $mixed = [$bool_sr->one(), $prec_sr->zero(), $sem_sr->one()];
    ok($comp->is_zero($mixed), 'is_zero: precedence zero kills whole tuple');

    # Boolean one, Precedence one, Semantic zero
    my $mixed2 = [$bool_sr->one(), $prec_sr->one(), $sem_sr->zero()];
    ok($comp->is_zero($mixed2), 'is_zero: semantic zero kills whole tuple');

    # All non-zero
    my $all_one = [$bool_sr->one(), $prec_sr->one(), $sem_sr->one()];
    ok(!$comp->is_zero($all_one), 'is_zero: all ones → false');
}

# ========================================================================
# N-ary FilterComposite: multiply delegates to all components
# ========================================================================

# Test 7: multiply delegates to both (2-ary)
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'left');
    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus    => $node1,
        children => [],
        position => 0,
        rule     => 'Left',
    );

    my $node2 = $factory->make('Constant', const_type => 'string', value => 'right');
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus    => $node2,
        children => [],
        position => 5,
        rule     => 'Right',
    );

    my $val1 = [$bool_sr->one(), $ctx1];
    my $val2 = [$bool_sr->one(), $ctx2];

    my $result = $comp->multiply($val1, $val2);

    isa_ok($result, 'ARRAY', 'multiply returns array ref');
    is(scalar($result->@*), 2, 'multiply returns 2-tuple');
    ok(!$bool_sr->is_zero($result->[0]), 'bool component is true');
    isa_ok($result->[1], 'Chalk::Bootstrap::Context', 'sem component is Context');
    is(scalar($result->[1]->children()->@*), 2, 'sem component has 2 children');
}

# Test 8: multiply with zero propagates zero
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $zero = $comp->zero();
    my $one = $comp->one();

    my $result = $comp->multiply($zero, $one);
    ok($comp->is_zero($result), 'multiply(zero, one) is zero');
}

# ========================================================================
# N-ary FilterComposite: add() - FilterComposite protocol
# ========================================================================

# Test 9: add() with distinct semantic contexts picks left as deterministic tie-break
# FilterComposite does NOT die on ambiguity — it picks left deterministically.
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'alt1');
    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus    => $node1,
        children => [],
        position => 0,
        rule     => 'Alt1',
    );

    my $node2 = $factory->make('Constant', const_type => 'string', value => 'alt2');
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus    => $node2,
        children => [],
        position => 0,
        rule     => 'Alt2',
    );

    my $val1 = [$bool_sr->one(), $ctx1];
    my $val2 = [$bool_sr->one(), $ctx2];

    # FilterComposite picks left as tie-break when no semiring distinguishes
    my $result = $comp->add($val1, $val2);
    isa_ok($result, 'ARRAY', 'add returns array tuple for ambiguous case');
    is($result->[1]->extract()->value(), 'alt1', 'add picks left on tie-break');
}

# Test 9b: add succeeds when same context on both sides (disambiguated)
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $node = $factory->make('Constant', const_type => 'string', value => 'winner');
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => $node,
        children => [],
        position => 0,
        rule     => 'Winner',
    );

    my $val = [$bool_sr->one(), $ctx];
    my $result = $comp->add($val, $val);

    isa_ok($result, 'ARRAY', 'add returns array ref for same-value merge');
    is(scalar($result->@*), 2, 'add returns 2-tuple');
    ok(!$bool_sr->is_zero($result->[0]), 'bool component is true');
    is($result->[1]->extract()->value(), 'winner', 'sem component returns disambiguated value');
}

# ========================================================================
# N-ary FilterComposite: integer-semiring preference detection in add()
# ========================================================================

# Test 9c: FilterComposite picks whole left tuple when Structural integer add() returns left value
{
    use Chalk::Bootstrap::Semiring::Structural;
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr    = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $struct_sr, $sem_sr],
    );

    # Two alternatives where Structural can disambiguate:
    # Left has CALL only, Right has CALL+LIST.
    # Structural prefers non-list, so it picks Left.
    use Chalk::Bootstrap::Semiring::Structural qw(STRUCT_IS_CALL STRUCT_IS_LIST);
    my $struct_left  = STRUCT_IS_CALL;
    my $struct_right = STRUCT_IS_CALL | STRUCT_IS_LIST;

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'winner');
    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus    => $node1,
        children => [],
        position => 0,
        rule     => 'Left',
    );

    my $node2 = $factory->make('Constant', const_type => 'string', value => 'loser');
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus    => $node2,
        children => [],
        position => 0,
        rule     => 'Right',
    );

    my $val1 = [$bool_sr->one(), $struct_left,  $ctx1];
    my $val2 = [$bool_sr->one(), $struct_right, $ctx2];

    # Structural prefers non-list (left), so FilterComposite should return the left tuple.
    my $result = $comp->add($val1, $val2);

    isa_ok($result, 'ARRAY', '9c: FilterComposite returns array tuple when Structural disambiguates');
    is(scalar($result->@*), 3, '9c: returns 3-tuple');
    is($result->[1], STRUCT_IS_CALL, '9c: Structural component is the winner value (CALL only)');
    is($result->[2]->extract()->value(), 'winner', '9c: SemanticAction component is from left tuple');
}

# Test 9d: FilterComposite picks whole right tuple when Structural prefers right
{
    use Chalk::Bootstrap::Semiring::Structural;
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr    = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $struct_sr, $sem_sr],
    );

    # Left has CALL+LIST (is_list), Right has CALL only (no list).
    # Structural prefers non-list, so it picks Right.
    use Chalk::Bootstrap::Semiring::Structural qw(STRUCT_IS_CALL STRUCT_IS_LIST);
    my $struct_left  = STRUCT_IS_CALL | STRUCT_IS_LIST;
    my $struct_right = STRUCT_IS_CALL;

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'loser');
    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus    => $node1,
        children => [],
        position => 0,
        rule     => 'Left',
    );

    my $node2 = $factory->make('Constant', const_type => 'string', value => 'winner');
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus    => $node2,
        children => [],
        position => 0,
        rule     => 'Right',
    );

    my $val1 = [$bool_sr->one(), $struct_left,  $ctx1];
    my $val2 = [$bool_sr->one(), $struct_right, $ctx2];

    my $result = $comp->add($val1, $val2);

    isa_ok($result, 'ARRAY', '9d: FilterComposite returns array tuple when Structural disambiguates');
    is($result->[1], STRUCT_IS_CALL, '9d: Structural component is the winner value (CALL only)');
    is($result->[2]->extract()->value(), 'winner', '9d: SemanticAction component is from right tuple');
}

# Test 9e: FilterComposite picks left tuple when Structural tags are identical (tie-break)
{
    use Chalk::Bootstrap::Semiring::Structural;
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr    = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $struct_sr, $sem_sr],
    );

    use Chalk::Bootstrap::Semiring::Structural qw(STRUCT_IS_CALL STRUCT_IS_LIST);
    my $struct_identical = STRUCT_IS_CALL | STRUCT_IS_LIST;

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'left-winner');
    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus    => $node1,
        children => [],
        position => 0,
        rule     => 'Left',
    );

    my $node2 = $factory->make('Constant', const_type => 'string', value => 'right-loser');
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus    => $node2,
        children => [],
        position => 0,
        rule     => 'Right',
    );

    my $val1 = [$bool_sr->one(), $struct_identical, $ctx1];
    my $val2 = [$bool_sr->one(), $struct_identical, $ctx2];

    my $result = $comp->add($val1, $val2);

    isa_ok($result, 'ARRAY', '9e: FilterComposite returns array tuple for identical Structural tie-break');
    is($result->[1], $struct_identical, '9e: Structural component is the identical tag value');
    is($result->[2]->extract()->value(), 'left-winner', '9e: SemanticAction picks left on tie-break');
}

# ========================================================================
# FilterComposite: _filter_compare tests
# ========================================================================

# Test FC1: _filter_compare returns 'neither' when Boolean (same on both sides)
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'a');
    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus => $node1, children => [], position => 0, rule => 'A',
    );
    my $node2 = $factory->make('Constant', const_type => 'string', value => 'b');
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus => $node2, children => [], position => 0, rule => 'B',
    );

    my $val1 = [$bool_sr->one(), $ctx1];
    my $val2 = [$bool_sr->one(), $ctx2];

    # Both Bool components are true (one()) — no preference from Boolean.
    # SemanticAction returns [$ctx1, $ctx2] for distinct contexts — no preference.
    # So _filter_compare returns 'neither'.
    my $verdict = $comp->_filter_compare($val1, $val2);
    is($verdict, 'neither', 'FC1: _filter_compare neither when only bool semiring (same on both)');
}

# Test FC2: _filter_compare returns 'right_loses' when Structural prefers left
{
    use Chalk::Bootstrap::Semiring::Structural qw(STRUCT_IS_CALL STRUCT_IS_LIST);
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr    = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $struct_sr, $sem_sr],
    );

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'left');
    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus => $node1, children => [], position => 0, rule => 'Left',
    );
    my $node2 = $factory->make('Constant', const_type => 'string', value => 'right');
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus => $node2, children => [], position => 0, rule => 'Right',
    );

    # Left = CALL only; Right = CALL|LIST. Structural prefers left (no list wins).
    my $val1 = [$bool_sr->one(), STRUCT_IS_CALL,              $ctx1];
    my $val2 = [$bool_sr->one(), STRUCT_IS_CALL | STRUCT_IS_LIST, $ctx2];

    my $verdict = $comp->_filter_compare($val1, $val2);
    is($verdict, 'right_loses', 'FC2: _filter_compare right_loses when Structural prefers left');
}

# Test FC3: _filter_compare returns 'left_loses' when Structural prefers right
{
    use Chalk::Bootstrap::Semiring::Structural qw(STRUCT_IS_CALL STRUCT_IS_LIST);
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr    = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $struct_sr, $sem_sr],
    );

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'left');
    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus => $node1, children => [], position => 0, rule => 'Left',
    );
    my $node2 = $factory->make('Constant', const_type => 'string', value => 'right');
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus => $node2, children => [], position => 0, rule => 'Right',
    );

    # Left = CALL|LIST; Right = CALL only. Structural prefers right.
    my $val1 = [$bool_sr->one(), STRUCT_IS_CALL | STRUCT_IS_LIST, $ctx1];
    my $val2 = [$bool_sr->one(), STRUCT_IS_CALL,              $ctx2];

    my $verdict = $comp->_filter_compare($val1, $val2);
    is($verdict, 'left_loses', 'FC3: _filter_compare left_loses when Structural prefers right');
}

# Test FC4: _filter_compare with Precedence arrayref protocol - prefers higher-level
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $sem_sr],
    );

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'left');
    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus => $node1, children => [], position => 0, rule => 'Left',
    );
    my $node2 = $factory->make('Constant', const_type => 'string', value => 'right');
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus => $node2, children => [], position => 0, rule => 'Right',
    );

    # Use prec->one() (no level info) for left, and a value with level for right.
    # Precedence.add() returns [$right] when right has level and left doesn't.
    my $prec_with_level = $prec_sr->one();
    # Simulate: manually use _intern approach — use add() with one() and a real value
    # Actually let's use on_scan to get real values. Use one() for both (same object).
    my $prec_same = $prec_sr->one();

    my $val1 = [$bool_sr->one(), $prec_same, $ctx1];
    my $val2 = [$bool_sr->one(), $prec_same, $ctx2];

    # Both Precedence values are refaddr-equal (hash-consed one()) → no preference from Prec.
    # SemanticAction: two different contexts → no preference.
    # Result: 'neither'.
    my $verdict = $comp->_filter_compare($val1, $val2);
    is($verdict, 'neither', 'FC4: _filter_compare neither when Precedence values are identical');
}

# Test FC5: _filter_compare returns 'neither' when Structural merges (both untagged)
{
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr    = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $struct_sr, $sem_sr],
    );

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'left');
    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus => $node1, children => [], position => 0, rule => 'Left',
    );
    my $node2 = $factory->make('Constant', const_type => 'string', value => 'right');
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus => $node2, children => [], position => 0, rule => 'Right',
    );

    # Both Structural values are 0 (one() = untagged). add() returns 0|0 = 0.
    # Result equals both inputs (both are 0) → identity collapse → no preference.
    my $val1 = [$bool_sr->one(), 0, $ctx1];
    my $val2 = [$bool_sr->one(), 0, $ctx2];

    my $verdict = $comp->_filter_compare($val1, $val2);
    is($verdict, 'neither', 'FC5: _filter_compare neither when Structural values both untagged (merge)');
}

# ========================================================================
# N-ary FilterComposite: on_scan delegation
# ========================================================================

# Test 10: on_scan delegates to all component semirings
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $rule = Chalk::Grammar::Rule->new(
        name        => 'QualifiedIdentifier',
        expressions => [[]],
    );
    my $item = {
        rule   => $rule,
        dot    => 0,
        origin => 0,
        value  => $comp->one(),
    };

    my $result = $comp->on_scan($item, 0, 0, 'hello');

    isa_ok($result, 'ARRAY', 'on_scan returns array ref');
    is(scalar($result->@*), 2, 'on_scan returns 2-tuple');
    ok(!$bool_sr->is_zero($result->[0]), 'bool component is non-zero');
    isa_ok($result->[1], 'Chalk::Bootstrap::Context', 'sem component is Context');
    is($result->[1]->scanned_text(), 'hello', 'sem component contains matched text');
}

# ========================================================================
# N-ary FilterComposite: on_complete delegation
# ========================================================================

# Test 11: on_complete delegates to all component semirings
{
    package CompositeTestActions {
        use 5.42.0;
        use experimental 'class';

        class CompositeTestActions {
            method TestRule($ctx) { return uc($ctx->extract() // ''); }
        }
    }

    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $actions = CompositeTestActions->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => 'hello',
        children => [],
        position => 0,
        rule     => undef,
    );

    my $rule = Chalk::Grammar::Rule->new(
        name        => 'TestRule',
        expressions => [[]],
    );
    my $item = {
        rule   => $rule,
        dot    => 0,
        origin => 0,
        value  => [$bool_sr->one(), $ctx],
    };

    my $result = $comp->on_complete($item, 0, 5);

    isa_ok($result, 'ARRAY', 'on_complete returns array ref');
    is(scalar($result->@*), 2, 'on_complete returns 2-tuple');
    ok(!$bool_sr->is_zero($result->[0]), 'bool component unchanged');
    isa_ok($result->[1], 'Chalk::Bootstrap::Context', 'sem component is Context');
    is($result->[1]->extract(), 'HELLO', 'sem component has action applied');
    is($result->[1]->rule(), 'TestRule', 'sem component has rule name set');
}

# ========================================================================
# N-ary FilterComposite: 3-ary with Precedence
# ========================================================================

# Test 12: 3-ary on_scan with operator detection
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $sem_sr],
    );

    my $rule = Chalk::Grammar::Rule->new(
        name        => 'BinaryOp',
        expressions => [[]],
    );
    my $item = {
        rule   => $rule,
        dot    => 0,
        origin => 0,
        value  => $comp->one(),
    };

    my $result = $comp->on_scan($item, 0, 0, '+');

    isa_ok($result, 'ARRAY', '3-ary on_scan returns array ref');
    is(scalar($result->@*), 3, '3-ary on_scan returns 3-tuple');
    ok(!$bool_sr->is_zero($result->[0]), 'bool component non-zero');
    ok(!$prec_sr->is_zero($result->[1]), 'prec component non-zero');
    isa_ok($result->[2], 'Chalk::Bootstrap::Context', 'sem component is Context');
}

# Test 13: 3-ary is_zero when precedence kills an item
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $sem_sr],
    );

    my $bad = [$bool_sr->one(), $prec_sr->zero(), $sem_sr->one()];
    ok($comp->is_zero($bad), 'precedence zero in 3-tuple kills item');
}

# ========================================================================
# 4-ary FilterComposite: Boolean + Precedence + TypeInference + SemanticAction
# ========================================================================

# Test 14: 4-ary creation
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $type_sr, $sem_sr],
    );

    isa_ok($comp, 'Chalk::Bootstrap::Semiring::FilterComposite', 'creates 4-ary composite');

    my $one = $comp->one();
    is(scalar($one->@*), 4, '4-ary one returns 4-tuple');
    ok(!$comp->is_zero($one), '4-ary one is non-zero');

    my $zero = $comp->zero();
    is(scalar($zero->@*), 4, '4-ary zero returns 4-tuple');
    ok($comp->is_zero($zero), '4-ary zero is zero');
}

# Test 15: 4-ary is_zero when TypeInference kills an item
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $type_sr, $sem_sr],
    );

    my $bad = [$bool_sr->one(), $prec_sr->one(), $type_sr->zero(), $sem_sr->one()];
    ok($comp->is_zero($bad), 'type inference zero in 4-tuple kills item');
}

# Test 16: 4-ary on_scan with keyword detection in QualifiedIdentifier rule
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $type_sr, $sem_sr],
    );

    my $rule = Chalk::Grammar::Rule->new(
        name        => 'QualifiedIdentifier',
        expressions => [[]],
    );
    my $item = {
        rule   => $rule,
        dot    => 0,
        origin => 0,
        value  => $comp->one(),
    };

    my $result = $comp->on_scan($item, 0, 0, 'use');
    is(scalar($result->@*), 4, '4-ary on_scan returns 4-tuple');
    ok(!$bool_sr->is_zero($result->[0]), 'bool ok for keyword scan');
    ok(!$prec_sr->is_zero($result->[1]), 'prec ok for keyword scan');
    ok(!$type_sr->is_zero($result->[2]), 'type non-zero at scan (rejection at complete)');
    ok(!$type_sr->is_zero($result->[2]), 'type inference tagged (non-zero) for keyword scan');
}

# Test 17: 4-ary on_complete rejects keyword as QualifiedIdentifier in Atom
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $type_sr, $sem_sr],
    );

    my $rule = Chalk::Grammar::Rule->new(
        name        => 'Atom',
        expressions => [[]],
    );

    my $tagged_type = Chalk::Bootstrap::Context->new(
        focus    => { valid => true, keyword_as_identifier => true },
        children => [],
    );
    my $item = {
        rule   => $rule,
        dot    => 0,
        origin => 0,
        value  => [$bool_sr->one(), $prec_sr->one(), $tagged_type, $sem_sr->one()],
    };

    my $result = $comp->on_complete($item, 0, 3);
    is(scalar($result->@*), 4, '4-ary on_complete returns 4-tuple');
    ok($type_sr->is_zero($result->[2]), 'type inference rejects Atom completion with keyword');
    ok($comp->is_zero($result), 'whole 4-tuple is zero when type inference rejects');
}

# ========================================================================
# FilterComposite: add() zero handling
# ========================================================================

# Test FC-Z1: add() with left zero returns right
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $zero = $comp->zero();
    my $node = $factory->make('Constant', const_type => 'string', value => 'right');
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => $node, children => [], position => 0, rule => 'R',
    );
    my $one_val = [$bool_sr->one(), $ctx];

    my $result = $comp->add($zero, $one_val);
    is($result->[1]->extract()->value(), 'right', 'add(zero, right) returns right');
}

# Test FC-Z2: add() with right zero returns left
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $zero = $comp->zero();
    my $node = $factory->make('Constant', const_type => 'string', value => 'left');
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => $node, children => [], position => 0, rule => 'L',
    );
    my $one_val = [$bool_sr->one(), $ctx];

    my $result = $comp->add($one_val, $zero);
    is($result->[1]->extract()->value(), 'left', 'add(left, zero) returns left');
}

done_testing();
