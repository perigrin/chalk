# ABOUTME: Tests scan-time filtering via multiply for all semirings.
# ABOUTME: Verifies keyword rejection and scan gating through the unified multiply protocol.
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
use Chalk::Bootstrap::Earley;
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Context;

# Helper: build an annotated scan Context (as Earley would create it)
sub make_scan_ctx($matched_text, $rule_name, $is_predicted_hash = {}) {
    return Chalk::Bootstrap::Context->new(
        focus       => $matched_text,
        position    => 0,
        annotations => {
            scan      => true,
            rule_name => $rule_name,
            alt_idx   => 0,
            predicted => $is_predicted_hash,
        },
    );
}

# ========================================================================
# Test 1: Boolean multiply with scan Context passes through (no rejection)
# ========================================================================
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $scan_ctx = make_scan_ctx('text', 'TestRule');

    my $result = $bool_sr->multiply($bool_sr->one(), $scan_ctx);
    ok(!$bool_sr->is_zero($result), 'Boolean: multiply with scan Context passes through');
}

# ========================================================================
# Test 2: Precedence multiply with scan Context passes through for non-operator
# ========================================================================
{
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );

    my $scan_ctx = make_scan_ctx('foo', 'QualifiedIdentifier');
    my $result = $prec_sr->multiply($prec_sr->one(), $scan_ctx);
    ok(!$prec_sr->is_zero($result), 'Precedence: scan of non-operator passes through');
}

# ========================================================================
# Test 3: TypeInference multiply with scan Context — non-keyword passes through
# ========================================================================
{
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );

    my $scan_ctx = make_scan_ctx('foo', 'QualifiedIdentifier', {});
    my $result = $type_sr->multiply($type_sr->one(), $scan_ctx);
    ok(!$type_sr->is_zero($result), 'TypeInference: non-keyword QualifiedIdentifier scan passes');
}

# ========================================================================
# Test 4: TypeInference multiply with scan Context — keyword rejected when rule predicted
# ========================================================================
{
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );

    # ClassDeclaration predicted: 'class' should be rejected as QualifiedIdentifier
    my $predicted = { ClassDeclaration => 1, ClassBlock => 1 };
    my $scan_ctx = make_scan_ctx('class', 'QualifiedIdentifier', $predicted);
    my $result = $type_sr->multiply($type_sr->one(), $scan_ctx);
    ok($type_sr->is_zero($result),
        'TypeInference: keyword class rejected when ClassDeclaration predicted');
}

# ========================================================================
# Test 5: TypeInference multiply — keyword admitted when no rule predicted (fat-arrow)
# ========================================================================
{
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );

    # No keyword-consuming rule predicted: 'class' admitted as identifier
    my $scan_ctx = make_scan_ctx('class', 'QualifiedIdentifier', {});
    my $result = $type_sr->multiply($type_sr->one(), $scan_ctx);
    ok(!$type_sr->is_zero($result),
        'TypeInference: class admitted as identifier when no keyword-rule predicted');
}

# ========================================================================
# Test 6: TypeInference multiply — non-QualifiedIdentifier rule passes
# ========================================================================
{
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );

    # Keyword-consuming rules predicted, but rule is BinaryOp (not QI) — passes
    my $predicted = { ClassDeclaration => 1 };
    my $scan_ctx = make_scan_ctx('class', 'BinaryOp', $predicted);
    my $result = $type_sr->multiply($type_sr->one(), $scan_ctx);
    ok(!$type_sr->is_zero($result),
        'TypeInference: keyword in non-QualifiedIdentifier rule always passes');
}

# ========================================================================
# Test 7: TypeInference — 'sub' rejected as QI when SubroutineDefinition predicted
# ========================================================================
{
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );

    my $predicted = { SubroutineDefinition => 1, SubroutineDeclaration => 1 };
    my $scan_ctx = make_scan_ctx('sub', 'QualifiedIdentifier', $predicted);
    my $result = $type_sr->multiply($type_sr->one(), $scan_ctx);
    ok($type_sr->is_zero($result),
        'TypeInference: sub rejected when SubroutineDefinition predicted');
}

# ========================================================================
# Test 8: TypeInference — 'my' rejected as QI when VariableDeclaration predicted
# ========================================================================
{
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );

    my $predicted = { VariableDeclaration => 1, ForeachLoop => 1 };
    my $scan_ctx = make_scan_ctx('my', 'QualifiedIdentifier', $predicted);
    my $result = $type_sr->multiply($type_sr->one(), $scan_ctx);
    ok($type_sr->is_zero($result),
        'TypeInference: my rejected when VariableDeclaration predicted');
}

# ========================================================================
# Test 9: TypeInference — namespace-qualified keyword passes (Foo::class)
# ========================================================================
{
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );

    my $predicted = { ClassDeclaration => 1, ClassBlock => 1 };
    my $scan_ctx = make_scan_ctx('Foo::class', 'QualifiedIdentifier', $predicted);
    my $result = $type_sr->multiply($type_sr->one(), $scan_ctx);
    ok(!$type_sr->is_zero($result),
        'TypeInference: Foo::class passes even when ClassDeclaration predicted');
}

# ========================================================================
# Test 10: Structural multiply with scan Context — transparent passthrough
# ========================================================================
{
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $scan_ctx = make_scan_ctx('foo', 'TestRule');

    my $result = $struct_sr->multiply($struct_sr->one(), $scan_ctx);
    ok(!$struct_sr->is_zero($result),
        'Structural: multiply with scan Context is transparent passthrough');
    is($result, $struct_sr->one(),
        'Structural: scan result equals left value (passthrough)');
}

# ========================================================================
# Test 11: FilterComposite multiply with scan Context — keyword rejected
# ========================================================================
{
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr   = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $type_sr   = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr    = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $type_sr, $struct_sr, $sem_sr],
    );

    my $predicted = { ClassDeclaration => 1, ClassBlock => 1 };
    my $scan_ctx = make_scan_ctx('class', 'QualifiedIdentifier', $predicted);

    my $result = $comp->multiply($comp->one(), $scan_ctx);
    ok($comp->is_zero($result),
        'FilterComposite: keyword class rejected when ClassDeclaration predicted');
}

# ========================================================================
# Test 12: FilterComposite multiply with scan Context — non-keyword passes
# ========================================================================
{
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr   = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $type_sr   = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr    = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $type_sr, $struct_sr, $sem_sr],
    );

    my $scan_ctx = make_scan_ctx('foo', 'QualifiedIdentifier', {});

    my $result = $comp->multiply($comp->one(), $scan_ctx);
    ok(!$comp->is_zero($result),
        'FilterComposite: non-keyword identifier passes through scan');
}

# ========================================================================
# Test 13: TypeInference — 'if' admitted when ConditionalStatement NOT predicted
# ========================================================================
{
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );

    my $scan_ctx = make_scan_ctx('if', 'QualifiedIdentifier', {});
    my $result = $type_sr->multiply($type_sr->one(), $scan_ctx);
    ok(!$type_sr->is_zero($result),
        'TypeInference: if admitted when ConditionalStatement NOT predicted');
}

# ========================================================================
# Test 14: TypeInference — 'if' rejected when ConditionalStatement predicted
# (TODO: if is a hard keyword now, always rejected as QI)
# ========================================================================
{
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );

    my $predicted = { ConditionalStatement => 1 };
    my $scan_ctx = make_scan_ctx('if', 'QualifiedIdentifier', $predicted);

    TODO: {
        local $TODO = 'if keyword rejection depends on KEYWORD_RULES configuration';
        my $result = $type_sr->multiply($type_sr->one(), $scan_ctx);
        ok($type_sr->is_zero($result),
            'TypeInference: if rejected when ConditionalStatement predicted');
    }
}

done_testing();
