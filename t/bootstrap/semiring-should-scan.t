# ABOUTME: Tests should_scan protocol across all semirings.
# ABOUTME: Verifies default behavior (return true) and FilterComposite short-circuit logic.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::Precedence;
use Chalk::Bootstrap::Semiring::TypeInference;
use Chalk::Bootstrap::Semiring::Structural;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Grammar::Perl::PrecedenceTable;
use Chalk::Grammar::Perl::KeywordTable;
use Chalk::Grammar::Perl::TypeLibrary;
use Chalk::Grammar::Rule;

# ========================================================================
# Test 1: Boolean semiring has should_scan method
# ========================================================================
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $rule = Chalk::Grammar::Rule->new(
        name => 'TestRule',
        expressions => [[]],
    );
    my $item = {
        rule => $rule,
        dot => 0,
        origin => 0,
        value => $bool_sr->one(),
    };

    my $is_predicted = sub($rule_name) { return false };

    ok($bool_sr->can('should_scan'), 'Boolean has should_scan method');
    my $result = $bool_sr->should_scan($item, 0, 0, 'text', $is_predicted);
    ok($result, 'Boolean should_scan returns true by default');
}

# ========================================================================
# Test 2: Precedence semiring has should_scan method
# ========================================================================
{
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $rule = Chalk::Grammar::Rule->new(
        name => 'TestRule',
        expressions => [[]],
    );
    my $item = {
        rule => $rule,
        dot => 0,
        origin => 0,
        value => $prec_sr->one(),
    };

    my $is_predicted = sub($rule_name) { return false };

    ok($prec_sr->can('should_scan'), 'Precedence has should_scan method');
    my $result = $prec_sr->should_scan($item, 0, 0, 'text', $is_predicted);
    ok($result, 'Precedence should_scan returns true by default');
}

# ========================================================================
# Test 3: TypeInference semiring has should_scan method
# ========================================================================
{
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );
    my $rule = Chalk::Grammar::Rule->new(
        name => 'TestRule',
        expressions => [[]],
    );
    my $item = {
        rule => $rule,
        dot => 0,
        origin => 0,
        value => $type_sr->one(),
    };

    my $is_predicted = sub($rule_name) { return false };

    ok($type_sr->can('should_scan'), 'TypeInference has should_scan method');
    my $result = $type_sr->should_scan($item, 0, 0, 'text', $is_predicted);
    ok($result, 'TypeInference should_scan returns true by default');
}

# ========================================================================
# Test 4: Structural semiring has should_scan method
# ========================================================================
{
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $rule = Chalk::Grammar::Rule->new(
        name => 'TestRule',
        expressions => [[]],
    );
    my $item = {
        rule => $rule,
        dot => 0,
        origin => 0,
        value => $struct_sr->one(),
    };

    my $is_predicted = sub($rule_name) { return false };

    ok($struct_sr->can('should_scan'), 'Structural has should_scan method');
    my $result = $struct_sr->should_scan($item, 0, 0, 'text', $is_predicted);
    ok($result, 'Structural should_scan returns true by default');
}

# ========================================================================
# Test 5: SemanticAction semiring has should_scan method
# ========================================================================
{
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $rule = Chalk::Grammar::Rule->new(
        name => 'TestRule',
        expressions => [[]],
    );
    my $item = {
        rule => $rule,
        dot => 0,
        origin => 0,
        value => $sem_sr->one(),
    };

    my $is_predicted = sub($rule_name) { return false };

    ok($sem_sr->can('should_scan'), 'SemanticAction has should_scan method');
    my $result = $sem_sr->should_scan($item, 0, 0, 'text', $is_predicted);
    ok($result, 'SemanticAction should_scan returns true by default');
}

# ========================================================================
# Test 6: FilterComposite should_scan returns true when all components return true
# ========================================================================
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $type_sr, $struct_sr, $sem_sr],
    );

    my $rule = Chalk::Grammar::Rule->new(
        name => 'TestRule',
        expressions => [[]],
    );
    my $item = {
        rule => $rule,
        dot => 0,
        origin => 0,
        value => $comp->one(),
    };

    my $is_predicted = sub($rule_name) { return false };

    ok($comp->can('should_scan'), 'FilterComposite has should_scan method');
    my $result = $comp->should_scan($item, 0, 0, 'text', $is_predicted);
    ok($result, 'FilterComposite should_scan returns true when all components return true');
}

# ========================================================================
# Test 7: FilterComposite should_scan returns false when any component returns false
# ========================================================================
{
    # Create a custom semiring that returns false from should_scan
    package TestFalseSemiring {
        use 5.42.0;
        use experimental 'class';

        class TestFalseSemiring {
            method zero() { return 0; }
            method one() { return 1; }
            method is_zero($value) { return $value == 0; }
            method multiply($left, $right) { return $left && $right ? 1 : 0; }
            method add($left, $right) { return $left || $right ? 1 : 0; }
            method on_scan($item, $alt_idx, $pos, $matched_text) { return 1; }
            method on_complete($item, $alt_idx, $pos) { return 1; }
            method should_scan($item, $alt_idx, $pos, $matched_text, $is_predicted) {
                return false;  # Always reject
            }
        }
    }

    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $false_sr = TestFalseSemiring->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $false_sr, $sem_sr],
    );

    my $rule = Chalk::Grammar::Rule->new(
        name => 'TestRule',
        expressions => [[]],
    );
    my $item = {
        rule => $rule,
        dot => 0,
        origin => 0,
        value => $comp->one(),
    };

    my $is_predicted = sub($rule_name) { return false };

    my $result = $comp->should_scan($item, 0, 0, 'text', $is_predicted);
    ok(!$result, 'FilterComposite should_scan returns false when any component returns false');
}

# ========================================================================
# Test 8: FilterComposite short-circuits on first false
# ========================================================================
{
    # Create a semiring that tracks if should_scan was called
    package TestTrackingSemiring {
        use 5.42.0;
        use experimental 'class';

        class TestTrackingSemiring {
            field $called :reader = false;

            method zero() { return 0; }
            method one() { return 1; }
            method is_zero($value) { return $value == 0; }
            method multiply($left, $right) { return $left && $right ? 1 : 0; }
            method add($left, $right) { return $left || $right ? 1 : 0; }
            method on_scan($item, $alt_idx, $pos, $matched_text) { return 1; }
            method on_complete($item, $alt_idx, $pos) { return 1; }
            method should_scan($item, $alt_idx, $pos, $matched_text, $is_predicted) {
                $called = true;
                return true;
            }
        }
    }

    package TestFalseSemiring2 {
        use 5.42.0;
        use experimental 'class';

        class TestFalseSemiring2 {
            method zero() { return 0; }
            method one() { return 1; }
            method is_zero($value) { return $value == 0; }
            method multiply($left, $right) { return $left && $right ? 1 : 0; }
            method add($left, $right) { return $left || $right ? 1 : 0; }
            method on_scan($item, $alt_idx, $pos, $matched_text) { return 1; }
            method on_complete($item, $alt_idx, $pos) { return 1; }
            method should_scan($item, $alt_idx, $pos, $matched_text, $is_predicted) {
                return false;
            }
        }
    }

    my $false_sr = TestFalseSemiring2->new();
    my $tracking_sr = TestTrackingSemiring->new();

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$false_sr, $tracking_sr],
    );

    my $rule = Chalk::Grammar::Rule->new(
        name => 'TestRule',
        expressions => [[]],
    );
    my $item = {
        rule => $rule,
        dot => 0,
        origin => 0,
        value => $comp->one(),
    };

    my $is_predicted = sub($rule_name) { return false };

    my $result = $comp->should_scan($item, 0, 0, 'text', $is_predicted);
    ok(!$result, 'FilterComposite should_scan returns false');
    ok(!$tracking_sr->called(), 'FilterComposite short-circuits - second semiring not called');
}

done_testing();
