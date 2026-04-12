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
use Chalk::Bootstrap::Semiring::Structural;

# Local aliases for fully-qualified structural constants
use constant {
    STRUCT_IS_CALL => Chalk::Bootstrap::Semiring::Structural::STRUCT_IS_CALL,
    STRUCT_IS_LIST => Chalk::Bootstrap::Semiring::Structural::STRUCT_IS_LIST,
};

# Reset factory for clean test environment
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Helper: build a Context with a given set of annotations (merges over defaults).
# Used to construct test inputs for methods that take Contexts with annotation slots.
sub ctx_with_annotations($focus, $extra_annotations) {
    return Chalk::Bootstrap::Context->new(
        focus       => $focus,
        children    => [],
        position    => 0,
        annotations => $extra_annotations,
    );
}

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

# Test 3: zero() returns a Context with is_zero=true
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $zero = $comp->zero();

    isa_ok($zero, 'Chalk::Bootstrap::Context', 'zero returns a Context');
    ok($zero->is_zero(), 'zero returns a Context with is_zero=true');
}

# Test 4: one() returns a Context with is_zero=false and annotation slots
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $one = $comp->one();

    isa_ok($one, 'Chalk::Bootstrap::Context', 'one returns a Context');
    ok(!$one->is_zero(), 'one returns a Context with is_zero=false');
    # [Boolean, SA]: no annotation semirings, but SA's cfg annotation is present
    ok(defined $one->annotations()->{cfg}, 'one has cfg annotation from SA');
}

# ========================================================================
# N-ary FilterComposite: is_zero (Context flag)
# ========================================================================

# Test 5: is_zero delegates to Context->is_zero()
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $zero = $comp->zero();
    my $one = $comp->one();

    ok($comp->is_zero($zero), 'is_zero: zero Context -> true');
    ok(!$comp->is_zero($one), 'is_zero: one Context -> false');
}

# Test 6: is_zero on a Context with is_zero=true kills the parse path
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $sem_sr],
    );

    # A zero Context (is_zero=true) represents a dead path regardless of annotations.
    my $dead = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [],
        position => 0,
        is_zero  => true,
    );
    ok($comp->is_zero($dead), 'is_zero: Context with is_zero=true -> true');

    # A live Context (is_zero=false) is not zero even if annotation slots exist.
    my $live = $comp->one();
    ok(!$comp->is_zero($live), 'is_zero: Context with is_zero=false -> false');
}

# ========================================================================
# N-ary FilterComposite: multiply delegates to all components
# ========================================================================

# Test 7: multiply delegates to SA (2-ary [Boolean, SA])
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

    my $result = $comp->multiply($ctx1, $ctx2);

    isa_ok($result, 'Chalk::Bootstrap::Context', 'multiply returns a Context');
    ok(!$result->is_zero(), 'multiply result is non-zero');
    is(scalar($result->children()->@*), 2, 'multiply result has 2 children');
}

# Test 8: multiply with zero Context propagates zero
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

# Test 9: add() with distinct contexts picks left as deterministic tie-break
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

    # FilterComposite picks left as tie-break when no annotation semiring distinguishes
    my $result = $comp->add($ctx1, $ctx2);
    isa_ok($result, 'Chalk::Bootstrap::Context', 'add returns a Context for ambiguous case');
    is($result->extract()->value(), 'alt1', 'add picks left on tie-break');
}

# Test 9b: add succeeds when same context on both sides
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

    my $result = $comp->add($ctx, $ctx);

    isa_ok($result, 'Chalk::Bootstrap::Context', 'add returns a Context for same-value merge');
    ok(!$result->is_zero(), 'add result is non-zero');
    is($result->extract()->value(), 'winner', 'add returns the shared value');
}

# ========================================================================
# N-ary FilterComposite: annotation-semiring preference detection in add()
# ========================================================================

# Helper: build a Context with a 'structural' annotation for Structural semiring tests.
sub ctx_with_structural($focus_value, $struct_tag, $rule = undef) {
    return Chalk::Bootstrap::Context->new(
        focus       => $focus_value,
        children    => [],
        position    => 0,
        rule        => $rule,
        annotations => { structural => $struct_tag },
    );
}

# Test 9c: FilterComposite picks left Context when Structural prefers left
{
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr    = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $struct_sr, $sem_sr],
    );

    # Left has CALL only; Right has CALL|LIST. Structural prefers non-list (left).
    my $node1 = $factory->make('Constant', const_type => 'string', value => 'winner');
    my $node2 = $factory->make('Constant', const_type => 'string', value => 'loser');

    my $ctx1 = ctx_with_structural($node1, STRUCT_IS_CALL,              'Left');
    my $ctx2 = ctx_with_structural($node2, STRUCT_IS_CALL | STRUCT_IS_LIST, 'Right');

    my $result = $comp->add($ctx1, $ctx2);

    isa_ok($result, 'Chalk::Bootstrap::Context', '9c: add returns a Context when Structural disambiguates');
    is($result->annotations()->{structural}, STRUCT_IS_CALL, '9c: structural annotation is the winner value (CALL only)');
    is($result->extract()->value(), 'winner', '9c: focus is from left Context');
}

# Test 9d: FilterComposite picks right Context when Structural prefers right
{
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr    = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $struct_sr, $sem_sr],
    );

    # Left has CALL|LIST; Right has CALL only. Structural prefers right.
    my $node1 = $factory->make('Constant', const_type => 'string', value => 'loser');
    my $node2 = $factory->make('Constant', const_type => 'string', value => 'winner');

    my $ctx1 = ctx_with_structural($node1, STRUCT_IS_CALL | STRUCT_IS_LIST, 'Left');
    my $ctx2 = ctx_with_structural($node2, STRUCT_IS_CALL,                  'Right');

    my $result = $comp->add($ctx1, $ctx2);

    isa_ok($result, 'Chalk::Bootstrap::Context', '9d: add returns a Context when Structural disambiguates');
    is($result->annotations()->{structural}, STRUCT_IS_CALL, '9d: structural annotation is the winner value (CALL only)');
    is($result->extract()->value(), 'winner', '9d: focus is from right Context');
}

# Test 9e: FilterComposite picks left Context on tie-break when Structural tags are identical
{
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr    = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $struct_sr, $sem_sr],
    );

    my $struct_identical = STRUCT_IS_CALL | STRUCT_IS_LIST;

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'left-winner');
    my $node2 = $factory->make('Constant', const_type => 'string', value => 'right-loser');

    my $ctx1 = ctx_with_structural($node1, $struct_identical, 'Left');
    my $ctx2 = ctx_with_structural($node2, $struct_identical, 'Right');

    my $result = $comp->add($ctx1, $ctx2);

    isa_ok($result, 'Chalk::Bootstrap::Context', '9e: add returns a Context for identical Structural tie-break');
    is($result->annotations()->{structural}, $struct_identical, '9e: structural annotation is the identical tag value');
    is($result->extract()->value(), 'left-winner', '9e: focus picks left on tie-break');
}

# ========================================================================
# FilterComposite: _filter_compare tests
# ========================================================================

# Test FC1: _filter_compare returns 'neither' for [Boolean, SA] — no annotation semirings
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

    # [Boolean, SA] has no annotation semirings — _filter_compare always returns 'neither'.
    my $verdict = $comp->_filter_compare($ctx1, $ctx2);
    is($verdict, 'neither', 'FC1: _filter_compare neither when no annotation semirings');
}

# Test FC2: _filter_compare returns 'right_loses' when Structural prefers left
{
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr    = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $struct_sr, $sem_sr],
    );

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'left');
    my $ctx1 = ctx_with_structural($node1, STRUCT_IS_CALL,                  'Left');

    my $node2 = $factory->make('Constant', const_type => 'string', value => 'right');
    my $ctx2 = ctx_with_structural($node2, STRUCT_IS_CALL | STRUCT_IS_LIST, 'Right');

    # Left = CALL only; Right = CALL|LIST. Structural prefers left (no list wins).
    my $verdict = $comp->_filter_compare($ctx1, $ctx2);
    is($verdict, 'right_loses', 'FC2: _filter_compare right_loses when Structural prefers left');
}

# Test FC3: _filter_compare returns 'left_loses' when Structural prefers right
{
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr    = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $struct_sr, $sem_sr],
    );

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'left');
    my $ctx1 = ctx_with_structural($node1, STRUCT_IS_CALL | STRUCT_IS_LIST, 'Left');

    my $node2 = $factory->make('Constant', const_type => 'string', value => 'right');
    my $ctx2 = ctx_with_structural($node2, STRUCT_IS_CALL,                  'Right');

    # Left = CALL|LIST; Right = CALL only. Structural prefers right.
    my $verdict = $comp->_filter_compare($ctx1, $ctx2);
    is($verdict, 'left_loses', 'FC3: _filter_compare left_loses when Structural prefers right');
}

# Test FC4: _filter_compare returns 'neither' when Precedence values are identical
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
    my $node2 = $factory->make('Constant', const_type => 'string', value => 'right');

    # Both Precedence values are refaddr-equal (hash-consed one()) → no preference from Prec.
    my $prec_same = $prec_sr->one();
    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus => $node1, children => [], position => 0, rule => 'Left',
        annotations => { precedence => $prec_same },
    );
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus => $node2, children => [], position => 0, rule => 'Right',
        annotations => { precedence => $prec_same },
    );

    my $verdict = $comp->_filter_compare($ctx1, $ctx2);
    is($verdict, 'neither', 'FC4: _filter_compare neither when Precedence values are identical');
}

# Test FC5: _filter_compare returns 'neither' when Structural values are both untagged (identity merge)
{
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr    = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $struct_sr, $sem_sr],
    );

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'left');
    my $node2 = $factory->make('Constant', const_type => 'string', value => 'right');

    # Both Structural values are 0 (one() = untagged). add() returns 0|0 = 0.
    # Result equals both inputs (both are 0) → identity collapse → no preference.
    my $ctx1 = ctx_with_structural($node1, 0, 'Left');
    my $ctx2 = ctx_with_structural($node2, 0, 'Right');

    my $verdict = $comp->_filter_compare($ctx1, $ctx2);
    is($verdict, 'neither', 'FC5: _filter_compare neither when Structural values both untagged (merge)');
}

# ========================================================================
# N-ary FilterComposite: on_scan delegation
# ========================================================================

# Test 10: on_scan delegates to SA, returns Context with scanned_text
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );

    my $result = $comp->on_scan($comp->one(), 'QualifiedIdentifier', 0, 0, 'hello');

    isa_ok($result, 'Chalk::Bootstrap::Context', 'on_scan returns a Context');
    ok(!$result->is_zero(), 'on_scan result is non-zero');
    is($result->scanned_text(), 'hello', 'on_scan result contains matched text');
}

# ========================================================================
# N-ary FilterComposite: on_complete delegation
# ========================================================================

# Test 11: on_complete delegates to SA, applies action, returns Context
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

    my $result = $comp->on_complete($ctx, 'TestRule', 0, 5, 0);

    isa_ok($result, 'Chalk::Bootstrap::Context', 'on_complete returns a Context');
    ok(!$result->is_zero(), 'on_complete result is non-zero');
    is($result->extract(), 'HELLO', 'on_complete has action applied');
    is($result->rule(), 'TestRule', 'on_complete has rule name set');
}

# ========================================================================
# N-ary FilterComposite: 3-ary with Precedence
# ========================================================================

# Test 12: 3-ary on_scan with operator detection returns Context with precedence annotation
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $sem_sr],
    );

    my $result = $comp->on_scan($comp->one(), 'BinaryOp', 0, 0, '+');

    isa_ok($result, 'Chalk::Bootstrap::Context', '3-ary on_scan returns a Context');
    ok(!$result->is_zero(), '3-ary on_scan result is non-zero');
    ok(defined $result->annotations()->{precedence}, '3-ary on_scan result has precedence annotation');
    ok(!$prec_sr->is_zero($result->annotations()->{precedence}), 'precedence annotation is non-zero');
}

# Test 13: 3-ary: a Context with is_zero=true is detected as zero
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $sem_sr],
    );

    my $dead = $comp->zero();
    ok($comp->is_zero($dead), 'zero Context kills parse path');
}

# ========================================================================
# 4-ary FilterComposite: Boolean + Precedence + TypeInference + SemanticAction
# ========================================================================

# Test 14: 4-ary creation, one() and zero() return Contexts
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
    isa_ok($one, 'Chalk::Bootstrap::Context', '4-ary one returns a Context');
    ok(!$one->is_zero(), '4-ary one is non-zero');
    ok(defined $one->annotations()->{precedence}, '4-ary one has precedence annotation');
    ok(defined $one->annotations()->{cfg},        '4-ary one has cfg annotation from SA');

    my $zero = $comp->zero();
    isa_ok($zero, 'Chalk::Bootstrap::Context', '4-ary zero returns a Context');
    ok($zero->is_zero(), '4-ary zero is zero');
}

# Test 15: 4-ary: zero Context is detected by is_zero
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

    my $dead = $comp->zero();
    ok($comp->is_zero($dead), 'zero Context kills parse path in 4-ary composite');
}

# Test 16: 4-ary on_scan with keyword in QualifiedIdentifier returns non-zero Context
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

    my $result = $comp->on_scan($comp->one(), 'QualifiedIdentifier', 0, 0, 'use');
    isa_ok($result, 'Chalk::Bootstrap::Context', '4-ary on_scan returns a Context');
    ok(!$result->is_zero(), '4-ary on_scan is non-zero (keyword rejection happens at complete)');
    ok(defined $result->annotations()->{precedence}, '4-ary on_scan has precedence annotation');
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

    my $result = $comp->add($zero, $ctx);
    is($result->extract()->value(), 'right', 'add(zero, right) returns right');
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

    my $result = $comp->add($ctx, $zero);
    is($result->extract()->value(), 'left', 'add(left, zero) returns left');
}

# ========================================================================
# TI→SA threading: FilterComposite passes TI result to SA via set_type_context
# ========================================================================

# Test: SA has set_type_context and current_type_context methods
{
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    ok($sa->can('set_type_context'), 'SA has set_type_context method');
    ok(defined &Chalk::Bootstrap::Semiring::SemanticAction::current_type_context,
       'SA has current_type_context class method');

    # Initially undef
    is(Chalk::Bootstrap::Semiring::SemanticAction->current_type_context(), undef,
       'current_type_context is initially undef');

    # Set and retrieve
    my $mock_ctx = Chalk::Bootstrap::Context->new(
        focus    => { valid => true, return_type => 'Void' },
        children => [],
        position => 0,
    );
    $sa->set_type_context($mock_ctx);
    is(Chalk::Bootstrap::Semiring::SemanticAction->current_type_context(), $mock_ctx,
       'current_type_context returns what was set');

    # Clean up
    $sa->set_type_context(undef);
}

# Test: FilterComposite.on_complete threads TI result to SA
# Uses a monkey-patched SA that records what set_type_context receives.
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $ti_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => sub { false },
        builtin_lookup => sub { undef },
    );
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();

    # Build a mock SA that records set_type_context calls
    my $captured_type_ctx;
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    # Monkey-patch set_type_context to capture the argument
    my $orig_set = $sa->can('set_type_context');
    no warnings 'redefine';
    local *Chalk::Bootstrap::Semiring::SemanticAction::set_type_context = sub($self_sa, $ctx) {
        $captured_type_ctx = $ctx;
        $self_sa->$orig_set($ctx);
    };
    use warnings 'redefine';

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $ti_sr, $struct_sr, $sa],
    );

    # Build a valid input Context for the 5-ary composite using comp->one()
    my $value = $comp->one();

    # Run on_complete
    my $result = $comp->on_complete($value, 'TestRule', 0, 1, 0);

    # TI is an annotation semiring. FilterComposite should have threaded TI's
    # on_complete result to SA via set_type_context before SA's on_complete ran.
    ok(defined $captured_type_ctx, 'FilterComposite threads TI result to SA');
}

done_testing();
