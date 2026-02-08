# ABOUTME: Tests for TypeInference semiring and KeywordTable for keyword disambiguation.
# ABOUTME: Verifies keyword detection at scan time and rejection at Identifier and QualifiedIdentifier completion.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

# ========================================================================
# KeywordTable tests
# ========================================================================

use_ok('Chalk::Grammar::Perl::KeywordTable');

# All 36 keywords should be recognized (33 \b keywords + 3 regex-prefix tokens)
my @keywords = qw(
    use class sub method ADJUST
    if unless elsif else
    while until for foreach
    my our state local field
    not and or xor
    eq ne lt gt le ge cmp isa x
    undef true false
    m s qr
);

for my $kw (@keywords) {
    ok(Chalk::Grammar::Perl::KeywordTable::is_keyword($kw),
        "is_keyword('$kw') returns true");
}

# Non-keywords should NOT be recognized
my @non_keywords = qw(
    return die warn push pop shift unshift
    keys values defined ref length chomp
    join split grep map sort print say sprintf
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
    keyword_check => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
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

# Scanning a keyword as Identifier → tag keyword_as_identifier
{
    my $item = make_item('Identifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'use');
    ok(!$ti->is_zero($result), 'scanning keyword as Identifier is non-zero at scan time');
    ok($result->{keyword_as_identifier}, 'scanning "use" as Identifier tags keyword_as_identifier');
}

# Scanning a non-keyword as Identifier → no tag
{
    my $item = make_item('Identifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'foo');
    ok(!$ti->is_zero($result), 'scanning non-keyword as Identifier is non-zero');
    ok(!$result->{keyword_as_identifier}, 'scanning "foo" as Identifier does not tag');
}

# Scanning a keyword in a non-Identifier rule → no tag
{
    my $item = make_item('BinaryOp', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'and');
    ok(!$ti->is_zero($result), 'scanning keyword in BinaryOp is non-zero');
    ok(!$result->{keyword_as_identifier}, 'scanning keyword in BinaryOp does not tag');
}

# Scanning with zero value propagates zero
{
    my $item = make_item('Identifier', $ti->zero());
    my $result = $ti->on_scan($item, 0, 0, 'foo');
    ok($ti->is_zero($result), 'scanning with zero propagates zero');
}

# All 33 keywords scanned as Identifier get tagged
for my $kw (@keywords) {
    my $item = make_item('Identifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, $kw);
    ok($result->{keyword_as_identifier}, "on_scan tags '$kw' as keyword_as_identifier");
}

# ========================================================================
# on_complete: rejection of keyword-as-identifier
# ========================================================================

# Identifier complete with keyword_as_identifier → zero
{
    my $tagged = { valid => true, keyword_as_identifier => true };
    my $item = make_item('Identifier', $tagged);
    my $result = $ti->on_complete($item, 0, 3);
    ok($ti->is_zero($result), 'Identifier completion with keyword_as_identifier returns zero');
}

# Identifier complete without tag → valid
{
    my $item = make_item('Identifier', $ti->one());
    my $result = $ti->on_complete($item, 0, 3);
    ok(!$ti->is_zero($result), 'Identifier completion without tag returns valid');
}

# Non-Identifier complete with tag → valid (clears flag)
{
    my $tagged = { valid => true, keyword_as_identifier => true };
    my $item = make_item('BinaryExpression', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'non-Identifier completion ignores keyword flag');
    ok(!$result->{keyword_as_identifier}, 'non-Identifier completion clears flag');
}

# ========================================================================
# Full chain: scan "use" as Identifier → complete → is_zero
# ========================================================================

{
    my $item = make_item('Identifier', $ti->one());
    my $scanned = $ti->on_scan($item, 0, 0, 'use');
    ok(!$ti->is_zero($scanned), 'chain step 1: scan "use" as Identifier is non-zero');
    ok($scanned->{keyword_as_identifier}, 'chain step 1: tagged');

    my $completed_item = make_item('Identifier', $scanned);
    my $completed = $ti->on_complete($completed_item, 0, 3);
    ok($ti->is_zero($completed), 'chain step 2: Identifier completion returns zero');
}

# Full chain for non-keyword: scan "foo" as Identifier → complete → valid
{
    my $item = make_item('Identifier', $ti->one());
    my $scanned = $ti->on_scan($item, 0, 0, 'foo');
    ok(!$ti->is_zero($scanned), 'non-keyword chain step 1: scan is non-zero');

    my $completed_item = make_item('Identifier', $scanned);
    my $completed = $ti->on_complete($completed_item, 0, 3);
    ok(!$ti->is_zero($completed), 'non-keyword chain step 2: completion is valid');
}

# Keyword scanned in proper context (e.g., UseDeclaration's /use\b/) → no rejection
# because the rule is not Identifier, the terminal matches differently
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

# QualifiedIdentifier complete with keyword_as_identifier → zero
{
    my $tagged = { valid => true, keyword_as_identifier => true };
    my $item = make_item('QualifiedIdentifier', $tagged);
    my $result = $ti->on_complete($item, 0, 3);
    ok($ti->is_zero($result), 'QualifiedIdentifier completion with keyword_as_identifier returns zero');
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
    ok($ti->is_zero($completed), 'QualifiedIdentifier chain: completion returns zero');
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
use TestPipeline qw(perl_pipeline build_perl_recognizer);

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

# Identifier completion still rejects keyword_as_identifier (existing behavior preserved)
{
    my $tagged = { valid => true, keyword_as_identifier => true };
    my $item = make_item('Identifier', $tagged);
    my $result = $ti->on_complete($item, 0, 3);
    ok($ti->is_zero($result), 'Identifier rejection still works after on_complete refactor');
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

done_testing;
