# ABOUTME: Tests for TypeInference semiring and KeywordTable for keyword disambiguation.
# ABOUTME: Verifies keyword detection at scan time and rejection at QualifiedIdentifier completion.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

# ========================================================================
# KeywordTable tests
# ========================================================================

use_ok('Chalk::Grammar::Perl::KeywordTable');
use_ok('Chalk::Grammar::Perl::TypeLibrary');

# All keywords: declarators, conjunctions, phase blocks, operators, literals,
# builtins, quoting prefixes, and special tokens
my @keywords = qw(
    use class sub method ADJUST package
    if unless elsif else
    while until for foreach
    my our state local field
    BEGIN CHECK UNITCHECK INIT END
    not and or xor
    eq ne lt gt le ge cmp isa x
    undef true false
    map grep
    qw q qq m s qr
    __SUB__
);

for my $kw (@keywords) {
    ok(Chalk::Grammar::Perl::KeywordTable::is_keyword($kw),
        "is_keyword('$kw') returns true");
}

# Non-keywords should NOT be recognized
my @non_keywords = qw(
    return die warn push pop shift unshift
    keys values defined ref length chomp
    join split sort print say sprintf
    foo bar baz hello world
    _  WS Program Expression
);

for my $word (@non_keywords) {
    ok(!Chalk::Grammar::Perl::KeywordTable::is_keyword($word),
        "is_keyword('$word') returns false");
}

# ========================================================================
# TypeInference semiring basic operations
# ========================================================================

use_ok('Chalk::Bootstrap::Semiring::TypeInference');

my $ti = Chalk::Bootstrap::Semiring::TypeInference->new(
    keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
    builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_validated_builtin,
    type_check     => \&Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type,
);

# zero/one/is_zero
{
    my $z = $ti->zero();
    ok($ti->is_zero($z), 'zero is zero');

    my $o = $ti->one();
    ok(!$ti->is_zero($o), 'one is not zero');

    ok(!$z->{valid}, 'zero has valid=false');
    ok($o->{valid}, 'one has valid=true');
}

# multiply
{
    my $o = $ti->one();
    my $z = $ti->zero();

    # one * one = one (non-zero)
    my $r1 = $ti->multiply($o, $o);
    ok(!$ti->is_zero($r1), 'one * one is non-zero');

    # zero * one = zero
    my $r2 = $ti->multiply($z, $o);
    ok($ti->is_zero($r2), 'zero * one is zero');

    # one * zero = zero
    my $r3 = $ti->multiply($o, $z);
    ok($ti->is_zero($r3), 'one * zero is zero');

    # keyword_as_identifier propagation
    my $tagged = { valid => true, keyword_as_identifier => true };

    my $r4 = $ti->multiply($tagged, $o);
    ok($r4->{keyword_as_identifier}, 'keyword_as_identifier propagates from left');

    my $r5 = $ti->multiply($o, $tagged);
    ok($r5->{keyword_as_identifier}, 'keyword_as_identifier propagates from right');
}

# add
{
    my $o = $ti->one();
    my $z = $ti->zero();

    # add(zero, one) = one
    my $r1 = $ti->add($z, $o);
    ok(!$ti->is_zero($r1), 'add(zero, one) is non-zero');

    # add(one, zero) = one
    my $r2 = $ti->add($o, $z);
    ok(!$ti->is_zero($r2), 'add(one, zero) is non-zero');

    # add(one, one) = first (one)
    my $r3 = $ti->add($o, $o);
    ok(!$ti->is_zero($r3), 'add(one, one) is non-zero');
}

# ========================================================================
# on_scan: keyword detection
# ========================================================================

use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;

# Helper to make an item
my sub make_item($rule_name, $value) {
    my $rule = Chalk::Grammar::Rule->new(
        name        => $rule_name,
        expressions => [[]],
    );
    return {
        rule   => $rule,
        dot    => 0,
        origin => 0,
        value  => $value,
    };
}

# Scanning a keyword as QualifiedIdentifier (bare) → tag keyword_as_identifier
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'use');
    ok(!$ti->is_zero($result), 'scanning keyword as QualifiedIdentifier is non-zero at scan time');
    ok($result->{keyword_as_identifier}, 'scanning "use" as QualifiedIdentifier tags keyword_as_identifier');
}

# Scanning a non-keyword as QualifiedIdentifier → no tag
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'foo');
    ok(!$ti->is_zero($result), 'scanning non-keyword as QualifiedIdentifier is non-zero');
    ok(!$result->{keyword_as_identifier}, 'scanning "foo" as QualifiedIdentifier does not tag');
}

# Scanning a keyword in a non-QualifiedIdentifier rule → no tag
{
    my $item = make_item('BinaryOp', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'and');
    ok(!$ti->is_zero($result), 'scanning keyword in BinaryOp is non-zero');
    ok(!$result->{keyword_as_identifier}, 'scanning keyword in BinaryOp does not tag');
}

# Scanning with zero value propagates zero
{
    my $item = make_item('QualifiedIdentifier', $ti->zero());
    my $result = $ti->on_scan($item, 0, 0, 'foo');
    ok($ti->is_zero($result), 'scanning with zero propagates zero');
}

# All keywords scanned as QualifiedIdentifier (bare) get tagged
for my $kw (@keywords) {
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, $kw);
    ok($result->{keyword_as_identifier}, "on_scan tags '$kw' as keyword_as_identifier");
}

# ========================================================================
# on_complete: rejection of keyword-as-identifier
# Rejection happens at Atom/CallExpression level, not QualifiedIdentifier.
# QualifiedIdentifier propagates the keyword_as_identifier tag upward.
# ========================================================================

# QualifiedIdentifier complete with keyword_as_identifier → valid (tag propagates)
{
    my $tagged = { valid => true, keyword_as_identifier => true };
    my $item = make_item('QualifiedIdentifier', $tagged);
    my $result = $ti->on_complete($item, 0, 3);
    ok(!$ti->is_zero($result), 'QualifiedIdentifier completion with keyword_as_identifier propagates (valid)');
    ok($result->{keyword_as_identifier}, 'QualifiedIdentifier preserves keyword_as_identifier tag');
}

# QualifiedIdentifier complete without tag → valid
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_complete($item, 0, 3);
    ok(!$ti->is_zero($result), 'QualifiedIdentifier completion without tag returns valid');
}

# Non-QualifiedIdentifier complete with tag → valid (preserves tag for propagation)
{
    my $tagged = { valid => true, keyword_as_identifier => true };
    my $item = make_item('BinaryExpression', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'non-QualifiedIdentifier completion ignores keyword flag');
    ok($result->{keyword_as_identifier}, 'non-QualifiedIdentifier completion preserves keyword_as_identifier tag');
}

# Atom complete with keyword_as_identifier → zero (expression-level rejection)
{
    my $tagged = { valid => true, keyword_as_identifier => true };
    my $item = make_item('Atom', $tagged);
    my $result = $ti->on_complete($item, 0, 3);
    ok($ti->is_zero($result), 'Atom completion with keyword_as_identifier returns zero');
}

# CallExpression complete with keyword_as_identifier → zero
{
    my $tagged = { valid => true, keyword_as_identifier => true };
    my $item = make_item('CallExpression', $tagged);
    my $result = $ti->on_complete($item, 0, 3);
    ok($ti->is_zero($result), 'CallExpression completion with keyword_as_identifier returns zero');
}

# Attribute complete with keyword_as_identifier → valid (boundary, clears tag)
{
    my $tagged = { valid => true, keyword_as_identifier => true };
    my $item = make_item('Attribute', $tagged);
    my $result = $ti->on_complete($item, 0, 3);
    ok(!$ti->is_zero($result), 'Attribute completion allows keyword identifiers');
    ok(!$result->{keyword_as_identifier}, 'Attribute clears keyword_as_identifier tag');
}

# ========================================================================
# Full chain: scan "use" as QualifiedIdentifier → complete → tag propagates → Atom rejects
# ========================================================================

{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $scanned = $ti->on_scan($item, 0, 0, 'use');
    ok(!$ti->is_zero($scanned), 'chain step 1: scan "use" as QualifiedIdentifier is non-zero');
    ok($scanned->{keyword_as_identifier}, 'chain step 1: tagged');

    my $completed_item = make_item('QualifiedIdentifier', $scanned);
    my $completed = $ti->on_complete($completed_item, 0, 3);
    ok(!$ti->is_zero($completed), 'chain step 2: QualifiedIdentifier completion propagates tag');
    ok($completed->{keyword_as_identifier}, 'chain step 2: tag preserved');

    # Atom would reject it
    my $atom_item = make_item('Atom', $completed);
    my $atom_result = $ti->on_complete($atom_item, 0, 3);
    ok($ti->is_zero($atom_result), 'chain step 3: Atom completion rejects keyword');
}

# Full chain for non-keyword: scan "foo" as QualifiedIdentifier → complete → valid
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $scanned = $ti->on_scan($item, 0, 0, 'foo');
    ok(!$ti->is_zero($scanned), 'non-keyword chain step 1: scan is non-zero');

    my $completed_item = make_item('QualifiedIdentifier', $scanned);
    my $completed = $ti->on_complete($completed_item, 0, 3);
    ok(!$ti->is_zero($completed), 'non-keyword chain step 2: completion is valid');
}

# Keyword scanned in proper context (e.g., UseDeclaration's /use\b/) → no rejection
# because the rule is not QualifiedIdentifier, the terminal matches differently
{
    my $item = make_item('UseDeclaration', $ti->one());
    my $scanned = $ti->on_scan($item, 0, 0, 'use');
    ok(!$ti->is_zero($scanned), 'keyword in proper context: scan is non-zero');
    ok(!$scanned->{keyword_as_identifier}, 'keyword in proper context: not tagged');

    my $completed_item = make_item('UseDeclaration', $scanned);
    my $completed = $ti->on_complete($completed_item, 0, 10);
    ok(!$ti->is_zero($completed), 'keyword in proper context: completion is valid');
}

# ========================================================================
# on_scan: QualifiedIdentifier keyword detection
# ========================================================================

# Scanning a bare keyword as QualifiedIdentifier → tag keyword_as_identifier
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'use');
    ok(!$ti->is_zero($result), 'scanning bare keyword as QualifiedIdentifier is non-zero at scan time');
    ok($result->{keyword_as_identifier}, 'scanning "use" as QualifiedIdentifier tags keyword_as_identifier');
}

# Scanning a qualified name containing a keyword → NOT tagged
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'Foo::class');
    ok(!$ti->is_zero($result), 'scanning qualified name as QualifiedIdentifier is non-zero');
    ok(!$result->{keyword_as_identifier}, 'scanning "Foo::class" as QualifiedIdentifier does NOT tag');
}

# Scanning a non-keyword as QualifiedIdentifier → NOT tagged
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'foo');
    ok(!$ti->is_zero($result), 'scanning non-keyword as QualifiedIdentifier is non-zero');
    ok(!$result->{keyword_as_identifier}, 'scanning "foo" as QualifiedIdentifier does NOT tag');
}

# All 33 keywords scanned as QualifiedIdentifier (bare) get tagged
for my $kw (@keywords) {
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, $kw);
    ok($result->{keyword_as_identifier}, "on_scan QualifiedIdentifier tags bare '$kw' as keyword_as_identifier");
}

# Qualified forms of keywords are NOT tagged
for my $kw (qw(use class sub method)) {
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, "Foo::$kw");
    ok(!$result->{keyword_as_identifier}, "on_scan QualifiedIdentifier does NOT tag 'Foo::$kw'");
}

# ========================================================================
# on_complete: QualifiedIdentifier keyword rejection
# ========================================================================

# QualifiedIdentifier complete with keyword_as_identifier → valid (tag propagates)
{
    my $tagged = { valid => true, keyword_as_identifier => true };
    my $item = make_item('QualifiedIdentifier', $tagged);
    my $result = $ti->on_complete($item, 0, 3);
    ok(!$ti->is_zero($result), 'QualifiedIdentifier completion with keyword_as_identifier propagates');
    ok($result->{keyword_as_identifier}, 'QualifiedIdentifier preserves keyword_as_identifier tag');
}

# QualifiedIdentifier complete without tag → valid
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_complete($item, 0, 3);
    ok(!$ti->is_zero($result), 'QualifiedIdentifier completion without tag returns valid');
}

# ========================================================================
# Full chain: scan "class" as QualifiedIdentifier → complete → is_zero
# ========================================================================

{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $scanned = $ti->on_scan($item, 0, 0, 'class');
    ok(!$ti->is_zero($scanned), 'QualifiedIdentifier chain: scan "class" is non-zero');
    ok($scanned->{keyword_as_identifier}, 'QualifiedIdentifier chain: tagged');

    my $completed_item = make_item('QualifiedIdentifier', $scanned);
    my $completed = $ti->on_complete($completed_item, 0, 5);
    ok(!$ti->is_zero($completed), 'QualifiedIdentifier chain: completion propagates tag');
    ok($completed->{keyword_as_identifier}, 'QualifiedIdentifier chain: tag preserved');
}

# Full chain for qualified name: scan "Foo::class" → complete → valid
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $scanned = $ti->on_scan($item, 0, 0, 'Foo::class');
    ok(!$ti->is_zero($scanned), 'QualifiedIdentifier qualified chain: scan is non-zero');
    ok(!$scanned->{keyword_as_identifier}, 'QualifiedIdentifier qualified chain: not tagged');

    my $completed_item = make_item('QualifiedIdentifier', $scanned);
    my $completed = $ti->on_complete($completed_item, 0, 10);
    ok(!$ti->is_zero($completed), 'QualifiedIdentifier qualified chain: completion is valid');
}

# ========================================================================
# on_scan: empty regex // rejection
# ========================================================================

# Empty regex // scanned as RegexLiteral → zero (this is defined-or operator)
{
    my $item = make_item('RegexLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '//');
    ok($ti->is_zero($result), 'scanning "//" as RegexLiteral returns zero');
}

# Empty regex with flags → also zero
{
    my $item = make_item('RegexLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '//i');
    ok($ti->is_zero($result), 'scanning "//i" as RegexLiteral returns zero');
}

# Empty regex //msixpodualngcer → zero (all flags)
{
    my $item = make_item('RegexLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '//msixpodualngcer');
    ok($ti->is_zero($result), 'scanning "//msixpodualngcer" as RegexLiteral returns zero');
}

# Real regex with pattern → NOT zero (accepted)
{
    my $item = make_item('RegexLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '/pattern/');
    ok(!$ti->is_zero($result), 'scanning "/pattern/" as RegexLiteral is NOT zero');
}

# Real regex with flags → NOT zero (accepted)
{
    my $item = make_item('RegexLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '/pattern/gi');
    ok(!$ti->is_zero($result), 'scanning "/pattern/gi" as RegexLiteral is NOT zero');
}

# Empty m// → zero (still an empty regex, just the m-form)
{
    my $item = make_item('RegexLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'm//');
    ok($ti->is_zero($result), 'scanning "m//" as RegexLiteral returns zero');
}

# m// with flags → zero
{
    my $item = make_item('RegexLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'm//i');
    ok($ti->is_zero($result), 'scanning "m//i" as RegexLiteral returns zero');
}

# m/pattern/ → NOT zero (real regex)
{
    my $item = make_item('RegexLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'm/pattern/');
    ok(!$ti->is_zero($result), 'scanning "m/pattern/" as RegexLiteral is NOT zero');
}

# BinaryOp scanning // → NOT zero (TypeInference doesn't touch BinaryOp)
{
    my $item = make_item('BinaryOp', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '//');
    ok(!$ti->is_zero($result), 'scanning "//" as BinaryOp is NOT zero');
}

# ========================================================================
# Integration: // and //= parse deterministically with TypeInference
# ========================================================================

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use TestPipeline qw(perl_pipeline build_perl_recognizer build_perl_concise_parser build_perl_ir_parser);

{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $ir = perl_pipeline();
    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::TIRegexTest/g;
    eval $generated;
    die "Generated code failed to compile: $@" if $@;

    my $gen_grammar = Chalk::Grammar::Perl::TIRegexTest::grammar();

    # Test defined-or: $a // $b
    {
        my $recognizer = build_perl_recognizer($gen_grammar, start => 'Program');
        my $result = $recognizer->parse('my $a = 1; my $b = 2; my $c = $a // $b;');
        ok($result, 'defined-or (//) parses with TypeInference pipeline');
    }

    # Test defined-or-assign: $a //= $b
    {
        my $recognizer = build_perl_recognizer($gen_grammar, start => 'Program');
        my $result = $recognizer->parse('my $a = 1; $a //= 2;');
        ok($result, 'defined-or-assign (//=) parses with TypeInference pipeline');
    }
}

# ========================================================================
# on_scan: ambiguous unary +/- tagging
# ========================================================================

# UnaryExpression scanning '+' with BinaryOp at same position → tagged ambiguous_unary
{
    # Simulate BinaryOp scanning at position 0 first (as happens in real parsing)
    my $bin_item = make_item('BinaryOp', $ti->one());
    $ti->on_scan($bin_item, 0, 0, '+');

    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '+');
    ok(!$ti->is_zero($result), 'scanning "+" as UnaryExpression (with BinaryOp) is non-zero');
    ok($result->{ambiguous_unary}, 'scanning "+" as UnaryExpression (with BinaryOp) tags ambiguous_unary');
}

# UnaryExpression scanning '-' with BinaryOp at same position → tagged ambiguous_unary
{
    my $bin_item = make_item('BinaryOp', $ti->one());
    $ti->on_scan($bin_item, 0, 1, '-');

    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 1, '-');
    ok(!$ti->is_zero($result), 'scanning "-" as UnaryExpression (with BinaryOp) is non-zero');
    ok($result->{ambiguous_unary}, 'scanning "-" as UnaryExpression (with BinaryOp) tags ambiguous_unary');
}

# UnaryExpression scanning '+' WITHOUT BinaryOp at same position → NOT tagged (standalone unary)
{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 99, '+');
    ok(!$ti->is_zero($result), 'scanning "+" as standalone UnaryExpression is non-zero');
    ok(!$result->{ambiguous_unary}, 'standalone "+" UnaryExpression NOT tagged');
}

# UnaryExpression scanning '-' WITHOUT BinaryOp → NOT tagged (standalone unary)
{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 100, '-');
    ok(!$ti->is_zero($result), 'scanning "-" as standalone UnaryExpression is non-zero');
    ok(!$result->{ambiguous_unary}, 'standalone "-" UnaryExpression NOT tagged');
}

# UnaryExpression scanning '!' → NOT tagged (unambiguous unary)
{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '!');
    ok(!$ti->is_zero($result), 'scanning "!" as UnaryExpression is non-zero');
    ok(!$result->{ambiguous_unary}, 'scanning "!" as UnaryExpression does NOT tag ambiguous_unary');
}

# UnaryExpression scanning '~' → NOT tagged
{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '~');
    ok(!$ti->is_zero($result), 'scanning "~" as UnaryExpression is non-zero');
    ok(!$result->{ambiguous_unary}, 'scanning "~" as UnaryExpression does NOT tag ambiguous_unary');
}

# UnaryExpression scanning 'not' → NOT tagged
{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'not');
    ok(!$ti->is_zero($result), 'scanning "not" as UnaryExpression is non-zero');
    ok(!$result->{ambiguous_unary}, 'scanning "not" as UnaryExpression does NOT tag ambiguous_unary');
}

# BinaryOp scanning '+' → NOT tagged (not a UnaryExpression)
{
    my $item = make_item('BinaryOp', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '+');
    ok(!$ti->is_zero($result), 'scanning "+" as BinaryOp is non-zero');
    ok(!$result->{ambiguous_unary}, 'scanning "+" as BinaryOp does NOT tag ambiguous_unary');
}

# ========================================================================
# multiply: ambiguous_unary propagation
# ========================================================================

{
    my $tagged = { valid => true, ambiguous_unary => true };
    my $o = $ti->one();

    my $r1 = $ti->multiply($tagged, $o);
    ok($r1->{ambiguous_unary}, 'ambiguous_unary propagates from left in multiply');

    my $r2 = $ti->multiply($o, $tagged);
    ok($r2->{ambiguous_unary}, 'ambiguous_unary propagates from right in multiply');

    # Both tagged
    my $r3 = $ti->multiply($tagged, $tagged);
    ok($r3->{ambiguous_unary}, 'ambiguous_unary propagates when both sides tagged');

    # Neither tagged
    my $r4 = $ti->multiply($o, $o);
    ok(!$r4->{ambiguous_unary}, 'ambiguous_unary not set when neither side tagged');
}

# ========================================================================
# on_complete: ambiguous_unary preservation and boundary clearing
# ========================================================================

# UnaryExpression completion with ambiguous_unary tag → rejected (binary path wins)
{
    my $tagged = { valid => true, ambiguous_unary => true };
    my $item = make_item('UnaryExpression', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok($ti->is_zero($result), 'UnaryExpression completion with ambiguous_unary returns zero');
}

# UnaryExpression completion WITHOUT tag → valid (standalone unary)
{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'UnaryExpression completion without tag is valid');
}

# Intermediate rule (Expression) preserves ambiguous_unary
{
    my $tagged = { valid => true, ambiguous_unary => true };
    my $item = make_item('Expression', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'Expression completion with ambiguous_unary is valid');
    ok($result->{ambiguous_unary}, 'Expression preserves ambiguous_unary');
}

# StatementItem preserves ambiguous_unary
{
    my $tagged = { valid => true, ambiguous_unary => true };
    my $item = make_item('StatementItem', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'StatementItem completion with ambiguous_unary is valid');
    ok($result->{ambiguous_unary}, 'StatementItem preserves ambiguous_unary');
}

# Boundary rule ParenExpr clears ambiguous_unary
{
    my $tagged = { valid => true, ambiguous_unary => true };
    my $item = make_item('ParenExpr', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'ParenExpr completion is valid');
    ok(!$result->{ambiguous_unary}, 'ParenExpr clears ambiguous_unary');
}

# Boundary rule Block clears ambiguous_unary
{
    my $tagged = { valid => true, ambiguous_unary => true };
    my $item = make_item('Block', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'Block completion is valid');
    ok(!$result->{ambiguous_unary}, 'Block clears ambiguous_unary');
}

# Boundary rule ArrayConstructor clears ambiguous_unary
{
    my $tagged = { valid => true, ambiguous_unary => true };
    my $item = make_item('ArrayConstructor', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'ArrayConstructor completion is valid');
    ok(!$result->{ambiguous_unary}, 'ArrayConstructor clears ambiguous_unary');
}

# Boundary rule HashConstructor clears ambiguous_unary
{
    my $tagged = { valid => true, ambiguous_unary => true };
    my $item = make_item('HashConstructor', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'HashConstructor completion is valid');
    ok(!$result->{ambiguous_unary}, 'HashConstructor clears ambiguous_unary');
}

# Boundary rule Signature clears ambiguous_unary
{
    my $tagged = { valid => true, ambiguous_unary => true };
    my $item = make_item('Signature', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'Signature completion is valid');
    ok(!$result->{ambiguous_unary}, 'Signature clears ambiguous_unary');
}

# QualifiedIdentifier completion propagates keyword_as_identifier (rejection at Atom/CallExpression)
{
    my $tagged = { valid => true, keyword_as_identifier => true };
    my $item = make_item('QualifiedIdentifier', $tagged);
    my $result = $ti->on_complete($item, 0, 3);
    ok(!$ti->is_zero($result), 'QualifiedIdentifier propagates keyword_as_identifier');
    ok($result->{keyword_as_identifier}, 'keyword_as_identifier tag preserved through QualifiedIdentifier');
}

# Non-boundary rule without tag → no ambiguous_unary
{
    my $item = make_item('BinaryExpression', $ti->one());
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'BinaryExpression completion is valid');
    ok(!$result->{ambiguous_unary}, 'BinaryExpression without tag has no ambiguous_unary');
}

# ========================================================================
# selects_alternative: prefer binary over ambiguous unary
# ========================================================================

{
    my $unary_tagged = { valid => true, ambiguous_unary => true };
    my $binary_clean = { valid => true };
    my $z = $ti->zero();

    # Left tagged, right clean → prefer right (binary)
    my $r1 = $ti->selects_alternative($unary_tagged, $binary_clean);
    is($r1, 'right', 'selects_alternative: left=unary, right=binary → right');

    # Left clean, right tagged → prefer left (binary)
    my $r2 = $ti->selects_alternative($binary_clean, $unary_tagged);
    is($r2, 'left', 'selects_alternative: left=binary, right=unary → left');

    # Both tagged → no preference
    my $r3 = $ti->selects_alternative($unary_tagged, $unary_tagged);
    is($r3, undef, 'selects_alternative: both tagged → undef');

    # Both clean → no preference
    my $r4 = $ti->selects_alternative($binary_clean, $binary_clean);
    is($r4, undef, 'selects_alternative: both clean → undef');

    # Left zero → no preference
    my $r5 = $ti->selects_alternative($z, $binary_clean);
    is($r5, undef, 'selects_alternative: left=zero → undef');

    # Right zero → no preference
    my $r6 = $ti->selects_alternative($binary_clean, $z);
    is($r6, undef, 'selects_alternative: right=zero → undef');
}

# ========================================================================
# add: prefer non-ambiguous-unary over ambiguous-unary
# ========================================================================

{
    my $unary_tagged = { valid => true, ambiguous_unary => true };
    my $binary_clean = { valid => true };

    # Left tagged, right clean → returns right (binary)
    my $r1 = $ti->add($unary_tagged, $binary_clean);
    ok(!$r1->{ambiguous_unary}, 'add: left=unary, right=binary → returns binary (no tag)');

    # Left clean, right tagged → returns left (binary)
    my $r2 = $ti->add($binary_clean, $unary_tagged);
    ok(!$r2->{ambiguous_unary}, 'add: left=binary, right=unary → returns binary (no tag)');

    # Both tagged → returns left (no preference)
    my $r3 = $ti->add($unary_tagged, $unary_tagged);
    ok($r3->{ambiguous_unary}, 'add: both tagged → returns left (still tagged)');

    # Both clean → returns left (no preference)
    my $r4 = $ti->add($binary_clean, $binary_clean);
    ok(!$r4->{ambiguous_unary}, 'add: both clean → returns left (no tag)');
}

# ========================================================================
# Integration: binary +/- parse deterministically with TypeInference
# ========================================================================

{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $ir = perl_pipeline();
    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::TIUnaryTest/g;
    eval $generated;
    die "Generated code failed to compile: $@" if $@;

    my $gen_grammar = Chalk::Grammar::Perl::TIUnaryTest::grammar();

    # Test binary addition: $a + $b
    {
        my $recognizer = build_perl_recognizer($gen_grammar, start => 'Program');
        my $result = $recognizer->parse('my $a = 1; my $b = 2; my $c = $a + $b;');
        ok($result, 'binary addition ($a + $b) parses with TypeInference pipeline');
    }

    # Test binary subtraction: $a - $b
    {
        my $recognizer = build_perl_recognizer($gen_grammar, start => 'Program');
        my $result = $recognizer->parse('my $a = 1; my $b = 2; my $c = $a - $b;');
        ok($result, 'binary subtraction ($a - $b) parses with TypeInference pipeline');
    }

    # Test chained: $a + $b - $c
    {
        my $recognizer = build_perl_recognizer($gen_grammar, start => 'Program');
        my $result = $recognizer->parse('my $a = 1; my $b = 2; my $c = 3; my $d = $a + $b - $c;');
        ok($result, 'chained addition-subtraction parses with TypeInference pipeline');
    }

    # Unambiguous unary still works: -$a
    {
        my $recognizer = build_perl_recognizer($gen_grammar, start => 'Program');
        my $result = $recognizer->parse('my $a = 1; my $b = -$a;');
        ok($result, 'unary negation (-$a) still parses');
    }

    # Unambiguous unary still works: +$a (unary plus, no binary context)
    {
        my $recognizer = build_perl_recognizer($gen_grammar, start => 'Program');
        my $result = $recognizer->parse('my $a = 1; my $b = +$a;');
        ok($result, 'unary plus (+$a) still parses');
    }
}

# ========================================================================
# Phase 1: Type tag propagation on Variables and PostfixDeref
# ========================================================================

# --- on_scan: variable type tagging ---

# ScalarVariable scanned → is_scalar_typed
{
    my $item = make_item('ScalarVariable', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '$x');
    ok(!$ti->is_zero($result), 'scanning $x as ScalarVariable is non-zero');
    ok($result->{is_scalar_typed}, 'scanning $x as ScalarVariable tags is_scalar_typed');
    ok(!$result->{is_array_typed}, 'scanning $x as ScalarVariable has no is_array_typed');
    ok(!$result->{is_hash_typed}, 'scanning $x as ScalarVariable has no is_hash_typed');
}

# ArrayVariable scanned → is_array_typed
{
    my $item = make_item('ArrayVariable', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '@arr');
    ok(!$ti->is_zero($result), 'scanning @arr as ArrayVariable is non-zero');
    ok($result->{is_array_typed}, 'scanning @arr as ArrayVariable tags is_array_typed');
    ok(!$result->{is_scalar_typed}, 'scanning @arr as ArrayVariable has no is_scalar_typed');
    ok(!$result->{is_hash_typed}, 'scanning @arr as ArrayVariable has no is_hash_typed');
}

# HashVariable scanned → is_hash_typed
{
    my $item = make_item('HashVariable', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '%h');
    ok(!$ti->is_zero($result), 'scanning %h as HashVariable is non-zero');
    ok($result->{is_hash_typed}, 'scanning %h as HashVariable tags is_hash_typed');
    ok(!$result->{is_scalar_typed}, 'scanning %h as HashVariable has no is_scalar_typed');
    ok(!$result->{is_array_typed}, 'scanning %h as HashVariable has no is_array_typed');
}

# --- multiply: type tag propagation ---

{
    my $scalar = { valid => true, is_scalar_typed => true };
    my $array  = { valid => true, is_array_typed => true };
    my $hash   = { valid => true, is_hash_typed => true };
    my $o = $ti->one();

    my $r1 = $ti->multiply($scalar, $o);
    ok($r1->{is_scalar_typed}, 'is_scalar_typed propagates from left in multiply');

    my $r2 = $ti->multiply($o, $array);
    ok($r2->{is_array_typed}, 'is_array_typed propagates from right in multiply');

    my $r3 = $ti->multiply($hash, $o);
    ok($r3->{is_hash_typed}, 'is_hash_typed propagates from left in multiply');

    # Multiple tags propagate together
    my $r4 = $ti->multiply($scalar, $array);
    ok($r4->{is_scalar_typed}, 'multiply: both scalar and array survive (scalar)');
    ok($r4->{is_array_typed}, 'multiply: both scalar and array survive (array)');
}

# --- on_complete: PostfixDeref type tagging ---

# PostfixDeref alt 0 (->@*) → is_array_typed
{
    my $item = make_item('PostfixDeref', $ti->one());
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'PostfixDeref alt 0 completion is valid');
    ok($result->{is_array_typed}, 'PostfixDeref alt 0 (->@*) tags is_array_typed');
}

# PostfixDeref alt 1 (->%*) → is_hash_typed
{
    my $item = make_item('PostfixDeref', $ti->one());
    my $result = $ti->on_complete($item, 1, 10);
    ok(!$ti->is_zero($result), 'PostfixDeref alt 1 completion is valid');
    ok($result->{is_hash_typed}, 'PostfixDeref alt 1 (->%*) tags is_hash_typed');
}

# PostfixDeref alt 2 (->$*) → is_scalar_typed
{
    my $item = make_item('PostfixDeref', $ti->one());
    my $result = $ti->on_complete($item, 2, 10);
    ok(!$ti->is_zero($result), 'PostfixDeref alt 2 completion is valid');
    ok($result->{is_scalar_typed}, 'PostfixDeref alt 2 (->$*) tags is_scalar_typed');
}

# PostfixDeref alt 3 (->$#*) → is_scalar_typed (array count is scalar)
{
    my $item = make_item('PostfixDeref', $ti->one());
    my $result = $ti->on_complete($item, 3, 10);
    ok(!$ti->is_zero($result), 'PostfixDeref alt 3 completion is valid');
    ok($result->{is_scalar_typed}, 'PostfixDeref alt 3 (->$#*) tags is_scalar_typed');
}

# --- on_complete: Variable propagates child type tags ---

{
    my $scalar_val = { valid => true, is_scalar_typed => true };
    my $item = make_item('Variable', $scalar_val);
    my $result = $ti->on_complete($item, 0, 5);
    ok(!$ti->is_zero($result), 'Variable completion with is_scalar_typed is valid');
    ok($result->{is_scalar_typed}, 'Variable preserves is_scalar_typed from child');
}

{
    my $array_val = { valid => true, is_array_typed => true };
    my $item = make_item('Variable', $array_val);
    my $result = $ti->on_complete($item, 0, 5);
    ok(!$ti->is_zero($result), 'Variable completion with is_array_typed is valid');
    ok($result->{is_array_typed}, 'Variable preserves is_array_typed from child');
}

# --- on_complete: boundary rules preserve type tags ---
# Type tags pass through boundary rules (unlike keyword_as_identifier)

{
    my $typed = { valid => true, is_array_typed => true };
    my $item = make_item('ParenExpr', $typed);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'ParenExpr with is_array_typed is valid');
    ok($result->{is_array_typed}, 'ParenExpr preserves is_array_typed');
    ok(!$result->{keyword_as_identifier}, 'ParenExpr still clears keyword_as_identifier');
}

{
    my $typed = { valid => true, is_scalar_typed => true, keyword_as_identifier => true };
    my $item = make_item('Block', $typed);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'Block with is_scalar_typed is valid');
    ok($result->{is_scalar_typed}, 'Block preserves is_scalar_typed');
    ok(!$result->{keyword_as_identifier}, 'Block still clears keyword_as_identifier');
}

# ========================================================================
# Phase 2: Builtin signature table and CallExpression validation
# ========================================================================

# --- on_scan: builtin name tagging ---

# Scanning 'push' as QualifiedIdentifier → call_symbol = 'push'
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'push');
    ok(!$ti->is_zero($result), 'scanning "push" as QualifiedIdentifier is non-zero');
    is($result->{call_symbol}, 'push',
        'scanning "push" as QualifiedIdentifier tags call_symbol => push');
    # push is NOT a keyword so it should NOT be keyword_as_identifier
    ok(!$result->{keyword_as_identifier},
        'scanning "push" as QualifiedIdentifier does NOT tag keyword_as_identifier');
}

# Scanning 'unshift' as QualifiedIdentifier → call_symbol = 'unshift'
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'unshift');
    is($result->{call_symbol}, 'unshift',
        'scanning "unshift" tags call_symbol => unshift');
}

# Scanning 'pop' as QualifiedIdentifier → call_symbol = 'pop'
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'pop');
    is($result->{call_symbol}, 'pop',
        'scanning "pop" tags call_symbol => pop');
}

# Scanning 'shift' as QualifiedIdentifier → call_symbol = 'shift'
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'shift');
    is($result->{call_symbol}, 'shift',
        'scanning "shift" tags call_symbol => shift');
}

# Scanning 'splice' as QualifiedIdentifier → call_symbol = 'splice'
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'splice');
    is($result->{call_symbol}, 'splice',
        'scanning "splice" tags call_symbol => splice');
}

# Scanning 'foo' → no call_symbol
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'foo');
    ok(!$result->{call_symbol},
        'scanning "foo" does NOT tag call_symbol');
}

# Qualified names (Foo::push) → no call_symbol
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'Foo::push');
    ok(!$result->{call_symbol},
        'scanning "Foo::push" does NOT tag call_symbol');
}

# --- multiply: call_symbol propagation ---

{
    my $builtin = { valid => true, call_symbol => 'push' };
    my $o = $ti->one();

    my $r1 = $ti->multiply($builtin, $o);
    is($r1->{call_symbol}, 'push',
        'call_symbol propagates from left in multiply');

    my $r2 = $ti->multiply($o, $builtin);
    is($r2->{call_symbol}, 'push',
        'call_symbol propagates from right in multiply');
}

# --- on_complete: CallExpression validates builtin first arg ---

# CallExpression with call_symbol=push, is_array_typed, list_arity 2 → valid
{
    my $val = { valid => true, call_symbol => 'push', is_array_typed => true, list_arity => 2 };
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'CallExpression: push with array arg and arity 2 → valid');
}

# CallExpression with call_symbol=push but only is_scalar_typed → zero (kill)
{
    my $val = { valid => true, call_symbol => 'push', is_scalar_typed => true };
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok($ti->is_zero($result), 'CallExpression: push with scalar-only arg → zero (killed)');
}

# CallExpression with call_symbol=push and NO type tags → zero (kill)
{
    my $val = { valid => true, call_symbol => 'push' };
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok($ti->is_zero($result), 'CallExpression: push with no type tags → zero (killed)');
}

# CallExpression with call_symbol=push, both scalar and array typed, list_arity 2 → valid
# (e.g., push @arr, $x — has both tags from multiply)
{
    my $val = { valid => true, call_symbol => 'push',
                is_array_typed => true, is_scalar_typed => true, list_arity => 2 };
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'CallExpression: push with array+scalar args → valid');
}

# CallExpression without call_symbol → normal (no validation)
{
    my $val = { valid => true, is_scalar_typed => true };
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'CallExpression: non-builtin with scalar → valid (no validation)');
}

# --- on_complete: ExpressionList tracks list_arity ---

# ExpressionList alt 0 (single Expression) → list_arity 1
{
    my $val = { valid => true, is_array_typed => true };
    my $item = make_item('ExpressionList', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'ExpressionList alt 0: valid');
    is($result->{list_arity}, 1, 'ExpressionList alt 0: list_arity = 1');
}

# ExpressionList alt 1 (ExpressionList , Expression) → list_arity from child + 1
{
    my $val = { valid => true, is_array_typed => true, list_arity => 1 };
    my $item = make_item('ExpressionList', $val);
    my $result = $ti->on_complete($item, 1, 10);
    ok(!$ti->is_zero($result), 'ExpressionList alt 1: valid');
    is($result->{list_arity}, 2, 'ExpressionList alt 1: list_arity = 2');
}

# ExpressionList alt 2 (ExpressionList => Expression) → list_arity from child + 1
{
    my $val = { valid => true, list_arity => 2 };
    my $item = make_item('ExpressionList', $val);
    my $result = $ti->on_complete($item, 2, 10);
    ok(!$ti->is_zero($result), 'ExpressionList alt 2: valid');
    is($result->{list_arity}, 3, 'ExpressionList alt 2: list_arity = 3');
}

# ExpressionList alt 3 (trailing comma) → list_arity preserved
{
    my $val = { valid => true, list_arity => 3 };
    my $item = make_item('ExpressionList', $val);
    my $result = $ti->on_complete($item, 3, 10);
    ok(!$ti->is_zero($result), 'ExpressionList alt 3: valid');
    is($result->{list_arity}, 3, 'ExpressionList alt 3: list_arity preserved');
}

# list_arity propagates through multiply
{
    my $left = { valid => true, list_arity => 2 };
    my $right = { valid => true, is_scalar_typed => true };
    my $result = $ti->multiply($left, $right);
    is($result->{list_arity}, 2, 'multiply: list_arity propagates from left');
}
{
    my $left = { valid => true };
    my $right = { valid => true, list_arity => 3 };
    my $result = $ti->multiply($left, $right);
    is($result->{list_arity}, 3, 'multiply: list_arity propagates from right');
}

# --- on_complete: CallExpression validates builtin min_arity ---

# push with list_arity 1 (only @arr, no values) → rejected (min_arity 2)
{
    my $val = { valid => true, call_symbol => 'push', is_array_typed => true, list_arity => 1 };
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 1, 10);
    ok($ti->is_zero($result), 'CallExpression: push with list_arity 1 → rejected (min_arity 2)');
}

# push with list_arity 2 (@arr, $val) → accepted
{
    my $val = { valid => true, call_symbol => 'push', is_array_typed => true, list_arity => 2 };
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 1, 10);
    ok(!$ti->is_zero($result), 'CallExpression: push with list_arity 2 → accepted');
}

# push with list_arity 3 (@arr, $val1, $val2) → accepted
{
    my $val = { valid => true, call_symbol => 'push', is_array_typed => true, list_arity => 3 };
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 1, 10);
    ok(!$ti->is_zero($result), 'CallExpression: push with list_arity 3 → accepted');
}

# pop with list_arity 1 (@arr) → accepted (min_arity 1)
{
    my $val = { valid => true, call_symbol => 'pop', is_array_typed => true, list_arity => 1 };
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 1, 10);
    ok(!$ti->is_zero($result), 'CallExpression: pop with list_arity 1 → accepted');
}

# list_arity cleared at boundary rules (ParenExpr, Block, etc.)
{
    my $val = { valid => true, list_arity => 3 };
    my $item = make_item('ParenExpr', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$result->{list_arity}, 'ParenExpr clears list_arity');
}

# --- on_complete: call_symbol cleared at boundary rules ---

{
    my $val = { valid => true, call_symbol => 'push' };
    my $item = make_item('ParenExpr', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$result->{call_symbol}, 'ParenExpr clears call_symbol');
}

{
    my $val = { valid => true, call_symbol => 'push' };
    my $item = make_item('Block', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$result->{call_symbol}, 'Block clears call_symbol');
}

# ========================================================================
# Hash builtin validation (keys, values, each)
# Currently disabled: get_validated_builtin restricts to Array-typed first
# args only, because call_symbol tags on hash builtins (keys, values, each)
# interfere with keyword expression parsing (e.g. `sort keys %h`).
# ========================================================================

TODO: {
    local $TODO = 'hash builtin validation disabled — call_symbol interferes with sort/grep/map';

    # Scanning 'keys' as QualifiedIdentifier → call_symbol = 'keys'
    {
        my $item = make_item('QualifiedIdentifier', $ti->one());
        my $result = $ti->on_scan($item, 0, 0, 'keys');
        is($result->{call_symbol}, 'keys',
            'scanning "keys" as QualifiedIdentifier tags call_symbol => keys');
    }

    # CallExpression with call_symbol=keys, is_hash_typed → valid
    {
        my $val = { valid => true, call_symbol => 'keys', is_hash_typed => true };
        my $item = make_item('CallExpression', $val);
        my $result = $ti->on_complete($item, 0, 10);
        ok(!$ti->is_zero($result), 'CallExpression: keys with hash arg → valid');
    }

    # CallExpression with call_symbol=keys, is_scalar_typed → zero (kill)
    {
        my $val = { valid => true, call_symbol => 'keys', is_scalar_typed => true };
        my $item = make_item('CallExpression', $val);
        my $result = $ti->on_complete($item, 0, 10);
        ok($ti->is_zero($result), 'CallExpression: keys with scalar arg → zero (killed)');
    }

    # CallExpression with call_symbol=keys, is_array_typed → zero (kill)
    {
        my $val = { valid => true, call_symbol => 'keys', is_array_typed => true };
        my $item = make_item('CallExpression', $val);
        my $result = $ti->on_complete($item, 0, 10);
        ok($ti->is_zero($result), 'CallExpression: keys with array arg → zero (killed)');
    }

    # CallExpression with call_symbol=keys, no type tags → zero (kill, strict)
    {
        my $val = { valid => true, call_symbol => 'keys' };
        my $item = make_item('CallExpression', $val);
        my $result = $ti->on_complete($item, 0, 10);
        ok($ti->is_zero($result), 'CallExpression: keys with no type tags → zero (killed)');
    }

    # CallExpression with call_symbol=values, is_hash_typed → valid
    {
        my $val = { valid => true, call_symbol => 'values', is_hash_typed => true };
        my $item = make_item('CallExpression', $val);
        my $result = $ti->on_complete($item, 0, 10);
        ok(!$ti->is_zero($result), 'CallExpression: values with hash arg → valid');
    }

    # CallExpression with call_symbol=each, is_hash_typed → valid
    {
        my $val = { valid => true, call_symbol => 'each', is_hash_typed => true };
        my $item = make_item('CallExpression', $val);
        my $result = $ti->on_complete($item, 0, 10);
        ok(!$ti->is_zero($result), 'CallExpression: each with hash arg → valid');
    }
}

# ========================================================================
# Non-array/hash builtins with Any arg type pass with any tags
# These builtins are not in get_validated_builtin, so on_complete skips
# validation entirely. They pass (valid) but not via type checking.
# ========================================================================

TODO: {
    local $TODO = 'non-array builtins not validated at parse time — get_validated_builtin returns undef';

    # CallExpression with call_symbol=defined, is_scalar_typed → valid (Any accepts all)
    {
        my $val = { valid => true, call_symbol => 'defined', is_scalar_typed => true };
        my $item = make_item('CallExpression', $val);
        my $result = $ti->on_complete($item, 0, 10);
        ok(!$ti->is_zero($result), 'CallExpression: defined with scalar arg → valid');
    }

    # CallExpression with call_symbol=die, no tags → valid (Any + min_arity 0)
    {
        my $val = { valid => true, call_symbol => 'die' };
        my $item = make_item('CallExpression', $val);
        my $result = $ti->on_complete($item, 0, 10);
        ok(!$ti->is_zero($result), 'CallExpression: die with no args → valid');
    }

    # CallExpression with call_symbol=warn, is_scalar_typed → valid
    {
        my $val = { valid => true, call_symbol => 'warn', is_scalar_typed => true };
        my $item = make_item('CallExpression', $val);
        my $result = $ti->on_complete($item, 0, 10);
        ok(!$ti->is_zero($result), 'CallExpression: warn with scalar arg → valid');
    }
}

# ========================================================================
# Integration: push/unshift with array args parse correctly
# ========================================================================

{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $ir = perl_pipeline();
    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::TIBuiltinTest/g;
    eval $generated;
    die "Generated code failed to compile: $@" if $@;

    my $gen_grammar = Chalk::Grammar::Perl::TIBuiltinTest::grammar();

    # push @arr, $x
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('push @arr, $x;');
        ok(defined $result && $result->[0], 'push @arr, $x: parses');
    }

    # push $ops->@*, $op (PostfixDeref provides array type)
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('push $ops->@*, $op;');
        ok(defined $result && $result->[0], 'push $ops->@*, $op: parses');
    }

    # unshift @arr, $x
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('unshift @arr, $x;');
        ok(defined $result && $result->[0], 'unshift @arr, $x: parses');
    }

    # pop @arr
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('pop @arr;');
        ok(defined $result && $result->[0], 'pop @arr: parses');
    }

    # shift @arr
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('shift @arr;');
        ok(defined $result && $result->[0], 'shift @arr: parses');
    }

    # splice @arr, 0, 1
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('splice @arr, 0, 1;');
        ok(defined $result && $result->[0], 'splice @arr, 0, 1: parses');
    }

    # Hash builtins: keys, values, each
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('keys %hash;');
        ok(defined $result && $result->[0], 'keys %hash: parses');
    }
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('values %hash;');
        ok(defined $result && $result->[0], 'values %hash: parses');
    }
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('each %hash;');
        ok(defined $result && $result->[0], 'each %hash: parses');
    }

    # Other new builtins: defined, warn, die, ref, length
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('defined $x;');
        ok(defined $result && $result->[0], 'defined $x: parses');
    }
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('warn "oops";');
        ok(defined $result && $result->[0], 'warn "oops": parses');
    }
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('die "fatal";');
        ok(defined $result && $result->[0], 'die "fatal": parses');
    }
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('ref $obj;');
        ok(defined $result && $result->[0], 'ref $obj: parses');
    }
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('length $str;');
        ok(defined $result && $result->[0], 'length $str: parses');
    }

    # Regression: existing expressions still parse
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('my $x = $a + $b;');
        ok(defined $result && $result->[0], 'regression: $a + $b still parses');
    }
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('my @r = map { $_ } @items;');
        ok(defined $result && $result->[0], 'regression: map {} @items still parses');
    }
    {
        my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
        my $result = $parser->parse_value('my $v = $h{$k};');
        ok(defined $result && $result->[0], 'regression: $h{$k} still parses');
    }
}

# ========================================================================
# Integration: push @arr, $x produces single BuiltinCall with 2 args
# (Validates that Earley fixed-point iteration propagates merged values
# to parent items, rather than fragmenting into separate statements.)
# ========================================================================

{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $ir = perl_pipeline();
    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::TIBuiltinIRTest/g;
    eval $generated;
    die "Generated code failed to compile: $@" if $@;

    my $gen_grammar = Chalk::Grammar::Perl::TIBuiltinIRTest::grammar();

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value('push @arr, $x;');
    ok(defined $result, 'push multi-arg IR: parse succeeds');

    if (defined $result) {
        my $sem_ctx = $result->[4];
        ok(defined $sem_ctx, 'push multi-arg IR: semantic context defined');

        if (defined $sem_ctx) {
            my $ir_node = $sem_ctx->extract();
            ok(defined $ir_node, 'push multi-arg IR: extract returns IR');

            if (defined $ir_node) {
                my $stmts = $ir_node->inputs()->[0];
                ok(ref $stmts eq 'ARRAY', 'push multi-arg IR: statements is array');

                if (ref $stmts eq 'ARRAY') {
                    is(scalar($stmts->@*), 1,
                        'push multi-arg IR: one statement (not fragmented)');

                    if (scalar($stmts->@*) >= 1) {
                        my $call = $stmts->[0];
                        ok($call isa Chalk::Bootstrap::IR::Node::Constructor,
                            'push multi-arg IR: stmt is Constructor');

                        if ($call isa Chalk::Bootstrap::IR::Node::Constructor) {
                            is($call->class(), 'BuiltinCall',
                                'push multi-arg IR: stmt is BuiltinCall');

                            if ($call->class() eq 'BuiltinCall') {
                                my $args = $call->inputs()->[1];
                                ok(ref $args eq 'ARRAY',
                                    'push multi-arg IR: args is array');
                                is(scalar($args->@*), 2,
                                    'push multi-arg IR: BuiltinCall has 2 args');
                            }
                        }
                    }
                }
            }
        }
    }
}

done_testing;
