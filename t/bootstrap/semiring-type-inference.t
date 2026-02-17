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
    map grep
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
use_ok('Chalk::Bootstrap::Context');

my $ti = Chalk::Bootstrap::Semiring::TypeInference->new(
    keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
    builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_validated_builtin,
    type_check     => \&Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type,
);

# Helper: create a leaf Context with tag hash focus (for test value construction)
my sub make_ctx(%tags) {
    return Chalk::Bootstrap::Context->new(
        focus    => { valid => true, %tags },
        children => [],
        position => 0,
        rule     => undef,
    );
}

# Helper: extract tag hash from a TypeInference value (Context tree).
# Mirrors the _tags() helper inside TypeInference.
my sub get_tags($val) {
    return undef unless defined $val;
    my $focus = $val->extract();
    return $focus if defined $focus;
    # Intermediate multiply node: collect from leaves
    my %merged;
    for my $leaf ($val->leaves()) {
        my $f = $leaf->extract();
        next unless defined $f;
        for my $k (keys %$f) {
            $merged{$k} = $f->{$k} if $f->{$k};
        }
    }
    return \%merged;
}

# zero/one/is_zero
{
    my $z = $ti->zero();
    ok($ti->is_zero($z), 'zero is zero');

    my $o = $ti->one();
    ok(!$ti->is_zero($o), 'one is not zero');

    ok(!defined $z, 'zero is undef');
    my $o_tags = get_tags($o);
    ok($o_tags->{valid}, 'one has valid=true');
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
    my $tagged = make_ctx(keyword_as_identifier => true);

    my $r4 = $ti->multiply($tagged, $o);
    ok(get_tags($r4)->{keyword_as_identifier}, 'keyword_as_identifier propagates from left');

    my $r5 = $ti->multiply($o, $tagged);
    ok(get_tags($r5)->{keyword_as_identifier}, 'keyword_as_identifier propagates from right');
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
    ok(get_tags($result)->{keyword_as_identifier}, 'scanning "use" as QualifiedIdentifier tags keyword_as_identifier');
}

# Scanning a non-keyword as QualifiedIdentifier → no tag
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'foo');
    ok(!$ti->is_zero($result), 'scanning non-keyword as QualifiedIdentifier is non-zero');
    ok(!get_tags($result)->{keyword_as_identifier}, 'scanning "foo" as QualifiedIdentifier does not tag');
}

# Scanning a keyword in a non-QualifiedIdentifier rule → no tag
{
    my $item = make_item('BinaryOp', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'and');
    ok(!$ti->is_zero($result), 'scanning keyword in BinaryOp is non-zero');
    ok(!get_tags($result)->{keyword_as_identifier}, 'scanning keyword in BinaryOp does not tag');
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
    ok(get_tags($result)->{keyword_as_identifier}, "on_scan tags '$kw' as keyword_as_identifier");
}

# ========================================================================
# on_complete: rejection of keyword-as-identifier
# Rejection happens at Atom/CallExpression level, not QualifiedIdentifier.
# QualifiedIdentifier propagates the keyword_as_identifier tag upward.
# ========================================================================

# QualifiedIdentifier complete with keyword_as_identifier → valid (tag propagates)
{
    my $tagged = make_ctx(keyword_as_identifier => true);
    my $item = make_item('QualifiedIdentifier', $tagged);
    my $result = $ti->on_complete($item, 0, 3);
    ok(!$ti->is_zero($result), 'QualifiedIdentifier completion with keyword_as_identifier propagates (valid)');
    ok(get_tags($result)->{keyword_as_identifier}, 'QualifiedIdentifier preserves keyword_as_identifier tag');
}

# QualifiedIdentifier complete without tag → valid
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_complete($item, 0, 3);
    ok(!$ti->is_zero($result), 'QualifiedIdentifier completion without tag returns valid');
}

# Non-QualifiedIdentifier complete with tag → valid (preserves tag for propagation)
{
    my $tagged = make_ctx(keyword_as_identifier => true);
    my $item = make_item('BinaryExpression', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'non-QualifiedIdentifier completion ignores keyword flag');
    ok(get_tags($result)->{keyword_as_identifier}, 'non-QualifiedIdentifier completion preserves keyword_as_identifier tag');
}

# Atom complete with keyword_as_identifier → zero (expression-level rejection)
{
    my $tagged = make_ctx(keyword_as_identifier => true);
    my $item = make_item('Atom', $tagged);
    my $result = $ti->on_complete($item, 0, 3);
    ok($ti->is_zero($result), 'Atom completion with keyword_as_identifier returns zero');
}

# CallExpression complete with keyword_as_identifier → zero
{
    my $tagged = make_ctx(keyword_as_identifier => true);
    my $item = make_item('CallExpression', $tagged);
    my $result = $ti->on_complete($item, 0, 3);
    ok($ti->is_zero($result), 'CallExpression completion with keyword_as_identifier returns zero');
}

# Attribute complete with keyword_as_identifier → valid (boundary, clears tag)
{
    my $tagged = make_ctx(keyword_as_identifier => true);
    my $item = make_item('Attribute', $tagged);
    my $result = $ti->on_complete($item, 0, 3);
    ok(!$ti->is_zero($result), 'Attribute completion allows keyword identifiers');
    ok(!get_tags($result)->{keyword_as_identifier}, 'Attribute clears keyword_as_identifier tag');
}

# ========================================================================
# Full chain: scan "use" as QualifiedIdentifier → complete → tag propagates → Atom rejects
# ========================================================================

{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $scanned = $ti->on_scan($item, 0, 0, 'use');
    ok(!$ti->is_zero($scanned), 'chain step 1: scan "use" as QualifiedIdentifier is non-zero');
    ok(get_tags($scanned)->{keyword_as_identifier}, 'chain step 1: tagged');

    my $completed_item = make_item('QualifiedIdentifier', $scanned);
    my $completed = $ti->on_complete($completed_item, 0, 3);
    ok(!$ti->is_zero($completed), 'chain step 2: QualifiedIdentifier completion propagates tag');
    ok(get_tags($completed)->{keyword_as_identifier}, 'chain step 2: tag preserved');

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
    ok(!get_tags($scanned)->{keyword_as_identifier}, 'keyword in proper context: not tagged');

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
    ok(get_tags($result)->{keyword_as_identifier}, 'scanning "use" as QualifiedIdentifier tags keyword_as_identifier');
}

# Scanning a qualified name containing a keyword → NOT tagged
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'Foo::class');
    ok(!$ti->is_zero($result), 'scanning qualified name as QualifiedIdentifier is non-zero');
    ok(!get_tags($result)->{keyword_as_identifier}, 'scanning "Foo::class" as QualifiedIdentifier does NOT tag');
}

# Scanning a non-keyword as QualifiedIdentifier → NOT tagged
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'foo');
    ok(!$ti->is_zero($result), 'scanning non-keyword as QualifiedIdentifier is non-zero');
    ok(!get_tags($result)->{keyword_as_identifier}, 'scanning "foo" as QualifiedIdentifier does NOT tag');
}

# All 33 keywords scanned as QualifiedIdentifier (bare) get tagged
for my $kw (@keywords) {
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, $kw);
    ok(get_tags($result)->{keyword_as_identifier}, "on_scan QualifiedIdentifier tags bare '$kw' as keyword_as_identifier");
}

# Qualified forms of keywords are NOT tagged
for my $kw (qw(use class sub method)) {
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, "Foo::$kw");
    ok(!get_tags($result)->{keyword_as_identifier}, "on_scan QualifiedIdentifier does NOT tag 'Foo::$kw'");
}

# ========================================================================
# on_complete: QualifiedIdentifier keyword rejection
# ========================================================================

# QualifiedIdentifier complete with keyword_as_identifier → valid (tag propagates)
{
    my $tagged = make_ctx(keyword_as_identifier => true);
    my $item = make_item('QualifiedIdentifier', $tagged);
    my $result = $ti->on_complete($item, 0, 3);
    ok(!$ti->is_zero($result), 'QualifiedIdentifier completion with keyword_as_identifier propagates');
    ok(get_tags($result)->{keyword_as_identifier}, 'QualifiedIdentifier preserves keyword_as_identifier tag');
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
    ok(get_tags($scanned)->{keyword_as_identifier}, 'QualifiedIdentifier chain: tagged');

    my $completed_item = make_item('QualifiedIdentifier', $scanned);
    my $completed = $ti->on_complete($completed_item, 0, 5);
    ok(!$ti->is_zero($completed), 'QualifiedIdentifier chain: completion propagates tag');
    ok(get_tags($completed)->{keyword_as_identifier}, 'QualifiedIdentifier chain: tag preserved');
}

# Full chain for qualified name: scan "Foo::class" → complete → valid
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $scanned = $ti->on_scan($item, 0, 0, 'Foo::class');
    ok(!$ti->is_zero($scanned), 'QualifiedIdentifier qualified chain: scan is non-zero');
    ok(!get_tags($scanned)->{keyword_as_identifier}, 'QualifiedIdentifier qualified chain: not tagged');

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
    ok(get_tags($result)->{ambiguous_unary}, 'scanning "+" as UnaryExpression (with BinaryOp) tags ambiguous_unary');
}

# UnaryExpression scanning '-' with BinaryOp at same position → tagged ambiguous_unary
{
    my $bin_item = make_item('BinaryOp', $ti->one());
    $ti->on_scan($bin_item, 0, 1, '-');

    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 1, '-');
    ok(!$ti->is_zero($result), 'scanning "-" as UnaryExpression (with BinaryOp) is non-zero');
    ok(get_tags($result)->{ambiguous_unary}, 'scanning "-" as UnaryExpression (with BinaryOp) tags ambiguous_unary');
}

# UnaryExpression scanning '+' WITHOUT BinaryOp at same position → NOT tagged (standalone unary)
{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 99, '+');
    ok(!$ti->is_zero($result), 'scanning "+" as standalone UnaryExpression is non-zero');
    ok(!get_tags($result)->{ambiguous_unary}, 'standalone "+" UnaryExpression NOT tagged');
}

# UnaryExpression scanning '-' WITHOUT BinaryOp → NOT tagged (standalone unary)
{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 100, '-');
    ok(!$ti->is_zero($result), 'scanning "-" as standalone UnaryExpression is non-zero');
    ok(!get_tags($result)->{ambiguous_unary}, 'standalone "-" UnaryExpression NOT tagged');
}

# UnaryExpression scanning '!' → NOT tagged (unambiguous unary)
{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '!');
    ok(!$ti->is_zero($result), 'scanning "!" as UnaryExpression is non-zero');
    ok(!get_tags($result)->{ambiguous_unary}, 'scanning "!" as UnaryExpression does NOT tag ambiguous_unary');
}

# UnaryExpression scanning '~' → NOT tagged
{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '~');
    ok(!$ti->is_zero($result), 'scanning "~" as UnaryExpression is non-zero');
    ok(!get_tags($result)->{ambiguous_unary}, 'scanning "~" as UnaryExpression does NOT tag ambiguous_unary');
}

# UnaryExpression scanning 'not' → NOT tagged
{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'not');
    ok(!$ti->is_zero($result), 'scanning "not" as UnaryExpression is non-zero');
    ok(!get_tags($result)->{ambiguous_unary}, 'scanning "not" as UnaryExpression does NOT tag ambiguous_unary');
}

# BinaryOp scanning '+' → NOT tagged (not a UnaryExpression)
{
    my $item = make_item('BinaryOp', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '+');
    ok(!$ti->is_zero($result), 'scanning "+" as BinaryOp is non-zero');
    ok(!get_tags($result)->{ambiguous_unary}, 'scanning "+" as BinaryOp does NOT tag ambiguous_unary');
}

# ========================================================================
# multiply: ambiguous_unary propagation
# ========================================================================

{
    my $tagged = make_ctx(ambiguous_unary => true);
    my $o = $ti->one();

    my $r1 = $ti->multiply($tagged, $o);
    ok(get_tags($r1)->{ambiguous_unary}, 'ambiguous_unary propagates from left in multiply');

    my $r2 = $ti->multiply($o, $tagged);
    ok(get_tags($r2)->{ambiguous_unary}, 'ambiguous_unary propagates from right in multiply');

    # Both tagged
    my $r3 = $ti->multiply($tagged, $tagged);
    ok(get_tags($r3)->{ambiguous_unary}, 'ambiguous_unary propagates when both sides tagged');

    # Neither tagged
    my $r4 = $ti->multiply($o, $o);
    ok(!get_tags($r4)->{ambiguous_unary}, 'ambiguous_unary not set when neither side tagged');
}

# ========================================================================
# on_complete: ambiguous_unary preservation and boundary clearing
# ========================================================================

# UnaryExpression completion with ambiguous_unary tag → rejected (binary path wins)
{
    my $tagged = make_ctx(ambiguous_unary => true);
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
    my $tagged = make_ctx(ambiguous_unary => true);
    my $item = make_item('Expression', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'Expression completion with ambiguous_unary is valid');
    ok(get_tags($result)->{ambiguous_unary}, 'Expression preserves ambiguous_unary');
}

# StatementItem preserves ambiguous_unary
{
    my $tagged = make_ctx(ambiguous_unary => true);
    my $item = make_item('StatementItem', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'StatementItem completion with ambiguous_unary is valid');
    ok(get_tags($result)->{ambiguous_unary}, 'StatementItem preserves ambiguous_unary');
}

# Boundary rule ParenExpr clears ambiguous_unary
{
    my $tagged = make_ctx(ambiguous_unary => true);
    my $item = make_item('ParenExpr', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'ParenExpr completion is valid');
    ok(!get_tags($result)->{ambiguous_unary}, 'ParenExpr clears ambiguous_unary');
}

# Boundary rule Block clears ambiguous_unary
{
    my $tagged = make_ctx(ambiguous_unary => true);
    my $item = make_item('Block', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'Block completion is valid');
    ok(!get_tags($result)->{ambiguous_unary}, 'Block clears ambiguous_unary');
}

# Boundary rule ArrayConstructor clears ambiguous_unary
{
    my $tagged = make_ctx(ambiguous_unary => true);
    my $item = make_item('ArrayConstructor', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'ArrayConstructor completion is valid');
    ok(!get_tags($result)->{ambiguous_unary}, 'ArrayConstructor clears ambiguous_unary');
}

# Boundary rule HashConstructor clears ambiguous_unary
{
    my $tagged = make_ctx(ambiguous_unary => true);
    my $item = make_item('HashConstructor', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'HashConstructor completion is valid');
    ok(!get_tags($result)->{ambiguous_unary}, 'HashConstructor clears ambiguous_unary');
}

# Boundary rule Signature clears ambiguous_unary
{
    my $tagged = make_ctx(ambiguous_unary => true);
    my $item = make_item('Signature', $tagged);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'Signature completion is valid');
    ok(!get_tags($result)->{ambiguous_unary}, 'Signature clears ambiguous_unary');
}

# QualifiedIdentifier completion propagates keyword_as_identifier (rejection at Atom/CallExpression)
{
    my $tagged = make_ctx(keyword_as_identifier => true);
    my $item = make_item('QualifiedIdentifier', $tagged);
    my $result = $ti->on_complete($item, 0, 3);
    ok(!$ti->is_zero($result), 'QualifiedIdentifier propagates keyword_as_identifier');
    ok(get_tags($result)->{keyword_as_identifier}, 'keyword_as_identifier tag preserved through QualifiedIdentifier');
}

# Non-boundary rule without tag → no ambiguous_unary
{
    my $item = make_item('BinaryExpression', $ti->one());
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'BinaryExpression completion is valid');
    ok(!get_tags($result)->{ambiguous_unary}, 'BinaryExpression without tag has no ambiguous_unary');
}

# ========================================================================
# selects_alternative: prefer binary over ambiguous unary
# ========================================================================

{
    my $unary_tagged = make_ctx(ambiguous_unary => true);
    my $binary_clean = make_ctx();
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
    my $unary_tagged = make_ctx(ambiguous_unary => true);
    my $binary_clean = make_ctx();

    # Left tagged, right clean → returns right (binary)
    my $r1 = $ti->add($unary_tagged, $binary_clean);
    ok(!get_tags($r1)->{ambiguous_unary}, 'add: left=unary, right=binary → returns binary (no tag)');

    # Left clean, right tagged → returns left (binary)
    my $r2 = $ti->add($binary_clean, $unary_tagged);
    ok(!get_tags($r2)->{ambiguous_unary}, 'add: left=binary, right=unary → returns binary (no tag)');

    # Both tagged → returns left (no preference)
    my $r3 = $ti->add($unary_tagged, $unary_tagged);
    ok(get_tags($r3)->{ambiguous_unary}, 'add: both tagged → returns left (still tagged)');

    # Both clean → returns left (no preference)
    my $r4 = $ti->add($binary_clean, $binary_clean);
    ok(!get_tags($r4)->{ambiguous_unary}, 'add: both clean → returns left (no tag)');
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
    my $tags = get_tags($result);
    ok($tags->{is_scalar_typed}, 'scanning $x as ScalarVariable tags is_scalar_typed');
    ok(!$tags->{is_array_typed}, 'scanning $x as ScalarVariable has no is_array_typed');
    ok(!$tags->{is_hash_typed}, 'scanning $x as ScalarVariable has no is_hash_typed');
}

# ArrayVariable scanned → is_array_typed
{
    my $item = make_item('ArrayVariable', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '@arr');
    ok(!$ti->is_zero($result), 'scanning @arr as ArrayVariable is non-zero');
    my $tags = get_tags($result);
    ok($tags->{is_array_typed}, 'scanning @arr as ArrayVariable tags is_array_typed');
    ok(!$tags->{is_scalar_typed}, 'scanning @arr as ArrayVariable has no is_scalar_typed');
    ok(!$tags->{is_hash_typed}, 'scanning @arr as ArrayVariable has no is_hash_typed');
}

# HashVariable scanned → is_hash_typed
{
    my $item = make_item('HashVariable', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '%h');
    ok(!$ti->is_zero($result), 'scanning %h as HashVariable is non-zero');
    my $tags = get_tags($result);
    ok($tags->{is_hash_typed}, 'scanning %h as HashVariable tags is_hash_typed');
    ok(!$tags->{is_scalar_typed}, 'scanning %h as HashVariable has no is_scalar_typed');
    ok(!$tags->{is_array_typed}, 'scanning %h as HashVariable has no is_array_typed');
}

# --- multiply: type tag propagation ---

{
    my $scalar = make_ctx(is_scalar_typed => true);
    my $array  = make_ctx(is_array_typed => true);
    my $hash   = make_ctx(is_hash_typed => true);
    my $o = $ti->one();

    my $r1 = $ti->multiply($scalar, $o);
    ok(get_tags($r1)->{is_scalar_typed}, 'is_scalar_typed propagates from left in multiply');

    my $r2 = $ti->multiply($o, $array);
    ok(get_tags($r2)->{is_array_typed}, 'is_array_typed propagates from right in multiply');

    my $r3 = $ti->multiply($hash, $o);
    ok(get_tags($r3)->{is_hash_typed}, 'is_hash_typed propagates from left in multiply');

    # Multiple tags propagate together
    my $r4 = $ti->multiply($scalar, $array);
    ok(get_tags($r4)->{is_scalar_typed}, 'multiply: both scalar and array survive (scalar)');
    ok(get_tags($r4)->{is_array_typed}, 'multiply: both scalar and array survive (array)');
}

# --- on_complete: PostfixDeref type tagging ---

# PostfixDeref alt 0 (->@*) → is_array_typed
{
    my $item = make_item('PostfixDeref', $ti->one());
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'PostfixDeref alt 0 completion is valid');
    ok(get_tags($result)->{is_array_typed}, 'PostfixDeref alt 0 (->@*) tags is_array_typed');
}

# PostfixDeref alt 1 (->%*) → is_hash_typed
{
    my $item = make_item('PostfixDeref', $ti->one());
    my $result = $ti->on_complete($item, 1, 10);
    ok(!$ti->is_zero($result), 'PostfixDeref alt 1 completion is valid');
    ok(get_tags($result)->{is_hash_typed}, 'PostfixDeref alt 1 (->%*) tags is_hash_typed');
}

# PostfixDeref alt 2 (->$*) → is_scalar_typed
{
    my $item = make_item('PostfixDeref', $ti->one());
    my $result = $ti->on_complete($item, 2, 10);
    ok(!$ti->is_zero($result), 'PostfixDeref alt 2 completion is valid');
    ok(get_tags($result)->{is_scalar_typed}, 'PostfixDeref alt 2 (->$*) tags is_scalar_typed');
}

# PostfixDeref alt 3 (->$#*) → is_scalar_typed (array count is scalar)
{
    my $item = make_item('PostfixDeref', $ti->one());
    my $result = $ti->on_complete($item, 3, 10);
    ok(!$ti->is_zero($result), 'PostfixDeref alt 3 completion is valid');
    ok(get_tags($result)->{is_scalar_typed}, 'PostfixDeref alt 3 (->$#*) tags is_scalar_typed');
}

# --- on_complete: Variable propagates child type tags ---

{
    my $scalar_val = make_ctx(is_scalar_typed => true);
    my $item = make_item('Variable', $scalar_val);
    my $result = $ti->on_complete($item, 0, 5);
    ok(!$ti->is_zero($result), 'Variable completion with is_scalar_typed is valid');
    ok(get_tags($result)->{is_scalar_typed}, 'Variable preserves is_scalar_typed from child');
}

{
    my $array_val = make_ctx(is_array_typed => true);
    my $item = make_item('Variable', $array_val);
    my $result = $ti->on_complete($item, 0, 5);
    ok(!$ti->is_zero($result), 'Variable completion with is_array_typed is valid');
    ok(get_tags($result)->{is_array_typed}, 'Variable preserves is_array_typed from child');
}

# --- on_complete: boundary rules preserve type tags ---
# Type tags pass through boundary rules (unlike keyword_as_identifier)

{
    my $typed = make_ctx(is_array_typed => true);
    my $item = make_item('ParenExpr', $typed);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'ParenExpr with is_array_typed is valid');
    ok(get_tags($result)->{is_array_typed}, 'ParenExpr preserves is_array_typed');
    ok(!get_tags($result)->{keyword_as_identifier}, 'ParenExpr still clears keyword_as_identifier');
}

{
    my $typed = make_ctx(is_scalar_typed => true, keyword_as_identifier => true);
    my $item = make_item('Block', $typed);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'Block with is_scalar_typed is valid');
    ok(get_tags($result)->{is_scalar_typed}, 'Block preserves is_scalar_typed');
    ok(!get_tags($result)->{keyword_as_identifier}, 'Block still clears keyword_as_identifier');
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
    is(get_tags($result)->{call_symbol}, 'push',
        'scanning "push" as QualifiedIdentifier tags call_symbol => push');
    # push is NOT a keyword so it should NOT be keyword_as_identifier
    ok(!get_tags($result)->{keyword_as_identifier},
        'scanning "push" as QualifiedIdentifier does NOT tag keyword_as_identifier');
}

# Scanning 'unshift' as QualifiedIdentifier → call_symbol = 'unshift'
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'unshift');
    is(get_tags($result)->{call_symbol}, 'unshift',
        'scanning "unshift" tags call_symbol => unshift');
}

# Scanning 'pop' as QualifiedIdentifier → call_symbol = 'pop'
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'pop');
    is(get_tags($result)->{call_symbol}, 'pop',
        'scanning "pop" tags call_symbol => pop');
}

# Scanning 'shift' as QualifiedIdentifier → call_symbol = 'shift'
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'shift');
    is(get_tags($result)->{call_symbol}, 'shift',
        'scanning "shift" tags call_symbol => shift');
}

# Scanning 'splice' as QualifiedIdentifier → call_symbol = 'splice'
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'splice');
    is(get_tags($result)->{call_symbol}, 'splice',
        'scanning "splice" tags call_symbol => splice');
}

# Scanning 'foo' → no call_symbol
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'foo');
    ok(!get_tags($result)->{call_symbol},
        'scanning "foo" does NOT tag call_symbol');
}

# Qualified names (Foo::push) → no call_symbol
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'Foo::push');
    ok(!get_tags($result)->{call_symbol},
        'scanning "Foo::push" does NOT tag call_symbol');
}

# --- multiply: call_symbol propagation ---

{
    my $builtin = make_ctx(call_symbol => 'push');
    my $o = $ti->one();

    my $r1 = $ti->multiply($builtin, $o);
    is(get_tags($r1)->{call_symbol}, 'push',
        'call_symbol propagates from left in multiply');

    my $r2 = $ti->multiply($o, $builtin);
    is(get_tags($r2)->{call_symbol}, 'push',
        'call_symbol propagates from right in multiply');
}

# --- on_complete: CallExpression validates builtin first arg ---

# CallExpression with call_symbol=push, is_array_typed, list_arity 2 → valid
{
    my $val = make_ctx(call_symbol => 'push', is_array_typed => true, list_arity => 2);
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'CallExpression: push with array arg and arity 2 → valid');
}

# CallExpression with call_symbol=push but only is_scalar_typed → zero (kill)
{
    my $val = make_ctx(call_symbol => 'push', is_scalar_typed => true);
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok($ti->is_zero($result), 'CallExpression: push with scalar-only arg → zero (killed)');
}

# CallExpression with call_symbol=push and NO type tags → zero (kill)
{
    my $val = make_ctx(call_symbol => 'push');
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok($ti->is_zero($result), 'CallExpression: push with no type tags → zero (killed)');
}

# CallExpression with call_symbol=push, both scalar and array typed, list_arity 2 → valid
# (e.g., push @arr, $x — has both tags from multiply)
{
    my $val = make_ctx(call_symbol => 'push',
                is_array_typed => true, is_scalar_typed => true, list_arity => 2);
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'CallExpression: push with array+scalar args → valid');
}

# CallExpression without call_symbol → normal (no validation)
{
    my $val = make_ctx(is_scalar_typed => true);
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'CallExpression: non-builtin with scalar → valid (no validation)');
}

# --- on_complete: ExpressionList tracks list_arity ---

# ExpressionList alt 0 (single Expression) → list_arity 1
{
    my $val = make_ctx(is_array_typed => true);
    my $item = make_item('ExpressionList', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'ExpressionList alt 0: valid');
    is(get_tags($result)->{list_arity}, 1, 'ExpressionList alt 0: list_arity = 1');
}

# ExpressionList alt 1 (ExpressionList , Expression) → list_arity from child + 1
{
    my $val = make_ctx(is_array_typed => true, list_arity => 1);
    my $item = make_item('ExpressionList', $val);
    my $result = $ti->on_complete($item, 1, 10);
    ok(!$ti->is_zero($result), 'ExpressionList alt 1: valid');
    is(get_tags($result)->{list_arity}, 2, 'ExpressionList alt 1: list_arity = 2');
}

# ExpressionList alt 2 (ExpressionList => Expression) → list_arity from child + 1
{
    my $val = make_ctx(list_arity => 2);
    my $item = make_item('ExpressionList', $val);
    my $result = $ti->on_complete($item, 2, 10);
    ok(!$ti->is_zero($result), 'ExpressionList alt 2: valid');
    is(get_tags($result)->{list_arity}, 3, 'ExpressionList alt 2: list_arity = 3');
}

# ExpressionList alt 3 (trailing comma) → list_arity preserved
{
    my $val = make_ctx(list_arity => 3);
    my $item = make_item('ExpressionList', $val);
    my $result = $ti->on_complete($item, 3, 10);
    ok(!$ti->is_zero($result), 'ExpressionList alt 3: valid');
    is(get_tags($result)->{list_arity}, 3, 'ExpressionList alt 3: list_arity preserved');
}

# list_arity propagates through multiply
{
    my $left = make_ctx(list_arity => 2);
    my $right = make_ctx(is_scalar_typed => true);
    my $result = $ti->multiply($left, $right);
    is(get_tags($result)->{list_arity}, 2, 'multiply: list_arity propagates from left');
}
{
    my $left = make_ctx();
    my $right = make_ctx(list_arity => 3);
    my $result = $ti->multiply($left, $right);
    is(get_tags($result)->{list_arity}, 3, 'multiply: list_arity propagates from right');
}

# --- on_complete: CallExpression validates builtin min_arity ---

# push with list_arity 1 (only @arr, no values) → rejected (min_arity 2)
{
    my $val = make_ctx(call_symbol => 'push', is_array_typed => true, list_arity => 1);
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 1, 10);
    ok($ti->is_zero($result), 'CallExpression: push with list_arity 1 → rejected (min_arity 2)');
}

# push with list_arity 2 (@arr, $val) → accepted
{
    my $val = make_ctx(call_symbol => 'push', is_array_typed => true, list_arity => 2);
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 1, 10);
    ok(!$ti->is_zero($result), 'CallExpression: push with list_arity 2 → accepted');
}

# push with list_arity 3 (@arr, $val1, $val2) → accepted
{
    my $val = make_ctx(call_symbol => 'push', is_array_typed => true, list_arity => 3);
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 1, 10);
    ok(!$ti->is_zero($result), 'CallExpression: push with list_arity 3 → accepted');
}

# pop with list_arity 1 (@arr) → accepted (min_arity 1)
{
    my $val = make_ctx(call_symbol => 'pop', is_array_typed => true, list_arity => 1);
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 1, 10);
    ok(!$ti->is_zero($result), 'CallExpression: pop with list_arity 1 → accepted');
}

# list_arity cleared at boundary rules (ParenExpr, Block, etc.)
{
    my $val = make_ctx(list_arity => 3);
    my $item = make_item('ParenExpr', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!get_tags($result)->{list_arity}, 'ParenExpr clears list_arity');
}

# --- on_complete: call_symbol cleared at boundary rules ---

{
    my $val = make_ctx(call_symbol => 'push');
    my $item = make_item('ParenExpr', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!get_tags($result)->{call_symbol}, 'ParenExpr clears call_symbol');
}

{
    my $val = make_ctx(call_symbol => 'push');
    my $item = make_item('Block', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!get_tags($result)->{call_symbol}, 'Block clears call_symbol');
}

# ========================================================================
# Hash builtin validation (keys, values, each)
# ========================================================================

# Scanning 'keys' as QualifiedIdentifier → call_symbol = 'keys'
{
    my $item = make_item('QualifiedIdentifier', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'keys');
    is(get_tags($result)->{call_symbol}, 'keys',
        'scanning "keys" as QualifiedIdentifier tags call_symbol => keys');
}

# CallExpression with call_symbol=keys, is_hash_typed → valid
{
    my $val = make_ctx(call_symbol => 'keys', is_hash_typed => true);
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'CallExpression: keys with hash arg → valid');
}

# CallExpression with call_symbol=keys, is_scalar_typed → zero (kill)
{
    my $val = make_ctx(call_symbol => 'keys', is_scalar_typed => true);
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok($ti->is_zero($result), 'CallExpression: keys with scalar arg → zero (killed)');
}

# CallExpression with call_symbol=keys, is_array_typed → zero (kill)
{
    my $val = make_ctx(call_symbol => 'keys', is_array_typed => true);
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok($ti->is_zero($result), 'CallExpression: keys with array arg → zero (killed)');
}

# CallExpression with call_symbol=keys, no type tags → zero (kill, strict)
{
    my $val = make_ctx(call_symbol => 'keys');
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok($ti->is_zero($result), 'CallExpression: keys with no type tags → zero (killed)');
}

# CallExpression with call_symbol=values, is_hash_typed → valid
{
    my $val = make_ctx(call_symbol => 'values', is_hash_typed => true);
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'CallExpression: values with hash arg → valid');
}

# CallExpression with call_symbol=each, is_hash_typed → valid
{
    my $val = make_ctx(call_symbol => 'each', is_hash_typed => true);
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'CallExpression: each with hash arg → valid');
}

# ========================================================================
# Non-array/hash builtins with Any arg type pass with any tags
# ========================================================================

# CallExpression with call_symbol=defined, is_scalar_typed → valid (Any accepts all)
{
    my $val = make_ctx(call_symbol => 'defined', is_scalar_typed => true);
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'CallExpression: defined with scalar arg → valid');
}

# CallExpression with call_symbol=die, no tags → valid (Any + min_arity 0)
{
    my $val = make_ctx(call_symbol => 'die');
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'CallExpression: die with no args → valid');
}

# CallExpression with call_symbol=warn, is_scalar_typed → valid
{
    my $val = make_ctx(call_symbol => 'warn', is_scalar_typed => true);
    my $item = make_item('CallExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'CallExpression: warn with scalar arg → valid');
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

# ========================================================================
# Phase 2: Scan-time type tags (type => 'TypeName')
# ========================================================================

# --- Variables get type tags alongside existing is_*_typed ---

# ScalarVariable → type => 'Scalar'
{
    my $item = make_item('ScalarVariable', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '$x');
    is(get_tags($result)->{type}, 'Scalar',
        'ScalarVariable scan tags type => Scalar');
}

# ArrayVariable → type => 'Array'
{
    my $item = make_item('ArrayVariable', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '@arr');
    is(get_tags($result)->{type}, 'Array',
        'ArrayVariable scan tags type => Array');
}

# HashVariable → type => 'Hash'
{
    my $item = make_item('HashVariable', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '%h');
    is(get_tags($result)->{type}, 'Hash',
        'HashVariable scan tags type => Hash');
}

# --- Literal type tags ---

# NumericLiteral: integer → type => 'Int'
{
    my $item = make_item('NumericLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '42');
    ok(!$ti->is_zero($result), 'NumericLiteral scan of "42" is non-zero');
    is(get_tags($result)->{type}, 'Int',
        'NumericLiteral "42" tags type => Int');
}

# NumericLiteral: hex integer → type => 'Int'
{
    my $item = make_item('NumericLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '0xFF');
    is(get_tags($result)->{type}, 'Int',
        'NumericLiteral "0xFF" tags type => Int');
}

# NumericLiteral: binary integer → type => 'Int'
{
    my $item = make_item('NumericLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '0b1010');
    is(get_tags($result)->{type}, 'Int',
        'NumericLiteral "0b1010" tags type => Int');
}

# NumericLiteral: octal integer → type => 'Int'
{
    my $item = make_item('NumericLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '0777');
    is(get_tags($result)->{type}, 'Int',
        'NumericLiteral "0777" tags type => Int');
}

# NumericLiteral: float → type => 'Num'
{
    my $item = make_item('NumericLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '3.14');
    is(get_tags($result)->{type}, 'Num',
        'NumericLiteral "3.14" tags type => Num');
}

# NumericLiteral: scientific notation → type => 'Num'
{
    my $item = make_item('NumericLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '1e10');
    is(get_tags($result)->{type}, 'Num',
        'NumericLiteral "1e10" tags type => Num');
}

# NumericLiteral: negative exponent → type => 'Num'
{
    my $item = make_item('NumericLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '2.5E-3');
    is(get_tags($result)->{type}, 'Num',
        'NumericLiteral "2.5E-3" tags type => Num');
}

# StringLiteral → type => 'Str'
{
    my $item = make_item('StringLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '"hello"');
    ok(!$ti->is_zero($result), 'StringLiteral scan of "hello" is non-zero');
    is(get_tags($result)->{type}, 'Str',
        'StringLiteral tags type => Str');
}

# StringLiteral: single-quoted → type => 'Str'
{
    my $item = make_item('StringLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, "'hello'");
    is(get_tags($result)->{type}, 'Str',
        'StringLiteral single-quoted tags type => Str');
}

# RegexLiteral (non-empty) → type => 'Regex'
{
    my $item = make_item('RegexLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '/pattern/');
    is(get_tags($result)->{type}, 'Regex',
        'RegexLiteral "/pattern/" tags type => Regex');
}

# RegexLiteral (empty, still rejected) → zero
{
    my $item = make_item('RegexLiteral', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '//');
    ok($ti->is_zero($result), 'RegexLiteral "//" still rejected');
}

# Literal: undef → type => 'Undef'
{
    my $item = make_item('Literal', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'undef');
    ok(!$ti->is_zero($result), 'Literal "undef" scan is non-zero');
    is(get_tags($result)->{type}, 'Undef',
        'Literal "undef" tags type => Undef');
}

# Literal: true → type => 'Bool'
{
    my $item = make_item('Literal', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'true');
    is(get_tags($result)->{type}, 'Bool',
        'Literal "true" tags type => Bool');
}

# Literal: false → type => 'Bool'
{
    my $item = make_item('Literal', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'false');
    is(get_tags($result)->{type}, 'Bool',
        'Literal "false" tags type => Bool');
}

# Atom: __SUB__ → type => 'CodeRef'
{
    my $item = make_item('Atom', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '__SUB__');
    ok(!$ti->is_zero($result), 'Atom __SUB__ scan is non-zero');
    is(get_tags($result)->{type}, 'CodeRef',
        'Atom "__SUB__" tags type => CodeRef');
}

# --- type tag propagation through multiply ---

{
    my $typed = make_ctx(type => 'Array');
    my $o = $ti->one();

    my $r1 = $ti->multiply($typed, $o);
    is(get_tags($r1)->{type}, 'Array',
        'type tag propagates from left in multiply');

    my $r2 = $ti->multiply($o, $typed);
    is(get_tags($r2)->{type}, 'Array',
        'type tag propagates from right in multiply');
}

# ========================================================================
# Phase 3: Scan-time op_text tags
# ========================================================================

# BinaryOp scans capture op_text
{
    my $item = make_item('BinaryOp', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '+');
    ok(!$ti->is_zero($result), 'BinaryOp "+" scan is non-zero');
    is(get_tags($result)->{op_text}, '+',
        'BinaryOp "+" tags op_text => +');
}

{
    my $item = make_item('BinaryOp', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '==');
    is(get_tags($result)->{op_text}, '==',
        'BinaryOp "==" tags op_text => ==');
}

{
    my $item = make_item('BinaryOp', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '.');
    is(get_tags($result)->{op_text}, '.',
        'BinaryOp "." tags op_text => .');
}

{
    my $item = make_item('BinaryOp', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, 'eq');
    is(get_tags($result)->{op_text}, 'eq',
        'BinaryOp "eq" tags op_text => eq');
}

{
    my $item = make_item('BinaryOp', $ti->one());
    my $result = $ti->on_scan($item, 0, 0, '&&');
    is(get_tags($result)->{op_text}, '&&',
        'BinaryOp "&&" tags op_text => &&');
}

# UnaryExpression operator scans capture op_text
{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 200, '!');
    is(get_tags($result)->{op_text}, '!',
        'UnaryExpression "!" tags op_text => !');
}

{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 201, 'not');
    is(get_tags($result)->{op_text}, 'not',
        'UnaryExpression "not" tags op_text => not');
}

{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 202, '~');
    is(get_tags($result)->{op_text}, '~',
        'UnaryExpression "~" tags op_text => ~');
}

{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 203, '\\');
    is(get_tags($result)->{op_text}, '\\',
        'UnaryExpression "\\" tags op_text => \\');
}

# Standalone unary - (no binary at same pos) still gets op_text but no ambiguous_unary
{
    my $item = make_item('UnaryExpression', $ti->one());
    my $result = $ti->on_scan($item, 0, 204, '-');
    is(get_tags($result)->{op_text}, '-',
        'standalone UnaryExpression "-" tags op_text => -');
    ok(!get_tags($result)->{ambiguous_unary},
        'standalone UnaryExpression "-" NOT tagged ambiguous_unary');
}

# op_text propagation through multiply
{
    my $op_tagged = make_ctx(op_text => '+');
    my $o = $ti->one();

    my $r1 = $ti->multiply($op_tagged, $o);
    is(get_tags($r1)->{op_text}, '+',
        'op_text propagates from left in multiply');

    my $r2 = $ti->multiply($o, $op_tagged);
    is(get_tags($r2)->{op_text}, '+',
        'op_text propagates from right in multiply');
}

# ========================================================================
# Phase 4: Complete-time type tags for compound Atoms
# ========================================================================

# AnonymousSub → type => 'Code'
{
    my $item = make_item('AnonymousSub', $ti->one());
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'AnonymousSub completion is valid');
    is(get_tags($result)->{type}, 'Code',
        'AnonymousSub tags type => Code');
}

# ArrayConstructor → type => 'ArrayRef'
{
    my $item = make_item('ArrayConstructor', $ti->one());
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'ArrayConstructor completion is valid');
    is(get_tags($result)->{type}, 'ArrayRef',
        'ArrayConstructor tags type => ArrayRef');
}

# HashConstructor → type => 'HashRef'
{
    my $item = make_item('HashConstructor', $ti->one());
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'HashConstructor completion is valid');
    is(get_tags($result)->{type}, 'HashRef',
        'HashConstructor tags type => HashRef');
}

# QwLiteral → type => 'List'
{
    my $item = make_item('QwLiteral', $ti->one());
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'QwLiteral completion is valid');
    is(get_tags($result)->{type}, 'List',
        'QwLiteral tags type => List');
}

# PostfixDeref alt 0 (->@*) → type => 'Array' (in addition to is_array_typed)
{
    my $item = make_item('PostfixDeref', $ti->one());
    my $result = $ti->on_complete($item, 0, 10);
    is(get_tags($result)->{type}, 'Array',
        'PostfixDeref alt 0 (->@*) tags type => Array');
}

# PostfixDeref alt 1 (->%*) → type => 'Hash'
{
    my $item = make_item('PostfixDeref', $ti->one());
    my $result = $ti->on_complete($item, 1, 10);
    is(get_tags($result)->{type}, 'Hash',
        'PostfixDeref alt 1 (->%*) tags type => Hash');
}

# PostfixDeref alt 2 (->$*) → type => 'Scalar'
{
    my $item = make_item('PostfixDeref', $ti->one());
    my $result = $ti->on_complete($item, 2, 10);
    is(get_tags($result)->{type}, 'Scalar',
        'PostfixDeref alt 2 (->$*) tags type => Scalar');
}

# PostfixDeref alt 3 (->$#*) → type => 'Scalar'
{
    my $item = make_item('PostfixDeref', $ti->one());
    my $result = $ti->on_complete($item, 3, 10);
    is(get_tags($result)->{type}, 'Scalar',
        'PostfixDeref alt 3 (->$#*) tags type => Scalar');
}

# ========================================================================
# Phase 5: Expression-level return types
# ========================================================================

# BinaryExpression with op_text '+' → type => 'Num' (consumes op_text)
{
    my $val = make_ctx(op_text => '+', type => 'Int');
    my $item = make_item('BinaryExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'BinaryExpression "+" is valid');
    is(get_tags($result)->{type}, 'Num',
        'BinaryExpression "+" tags type => Num');
    ok(!get_tags($result)->{op_text},
        'BinaryExpression consumes op_text');
}

# BinaryExpression with op_text '==' → type => 'Bool'
{
    my $val = make_ctx(op_text => '==');
    my $item = make_item('BinaryExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    is(get_tags($result)->{type}, 'Bool',
        'BinaryExpression "==" tags type => Bool');
}

# BinaryExpression with op_text '.' → type => 'Str'
{
    my $val = make_ctx(op_text => '.');
    my $item = make_item('BinaryExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    is(get_tags($result)->{type}, 'Str',
        'BinaryExpression "." tags type => Str');
}

# BinaryExpression with op_text '&&' → type => 'Any'
{
    my $val = make_ctx(op_text => '&&');
    my $item = make_item('BinaryExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    is(get_tags($result)->{type}, undef,
        'BinaryExpression "&&" tags type => undef (Any means unknown)');
}

# BinaryExpression with op_text '=~' → type => 'Bool'
{
    my $val = make_ctx(op_text => '=~');
    my $item = make_item('BinaryExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    is(get_tags($result)->{type}, 'Bool',
        'BinaryExpression "=~" tags type => Bool');
}

# BinaryExpression with op_text '..' → type => 'List'
{
    my $val = make_ctx(op_text => '..');
    my $item = make_item('BinaryExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    is(get_tags($result)->{type}, 'List',
        'BinaryExpression ".." tags type => List');
}

# BinaryExpression without op_text → type preserved from children
{
    my $val = make_ctx(type => 'Int');
    my $item = make_item('BinaryExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    is(get_tags($result)->{type}, 'Int',
        'BinaryExpression without op_text preserves child type');
}

# UnaryExpression with op_text '!' → type => 'Bool' (consumes op_text)
{
    my $val = make_ctx(op_text => '!');
    my $item = make_item('UnaryExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'UnaryExpression "!" is valid');
    is(get_tags($result)->{type}, 'Bool',
        'UnaryExpression "!" tags type => Bool');
    ok(!get_tags($result)->{op_text},
        'UnaryExpression consumes op_text');
}

# UnaryExpression with op_text '-' (standalone, no ambiguous) → type => 'Num'
{
    my $val = make_ctx(op_text => '-');
    my $item = make_item('UnaryExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    is(get_tags($result)->{type}, 'Num',
        'UnaryExpression "-" tags type => Num');
}

# UnaryExpression with op_text '\\' → type => 'Ref'
{
    my $val = make_ctx(op_text => '\\');
    my $item = make_item('UnaryExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    is(get_tags($result)->{type}, 'Ref',
        'UnaryExpression "\\" tags type => Ref');
}

# UnaryExpression with ambiguous_unary still rejected
{
    my $val = make_ctx(op_text => '+', ambiguous_unary => true);
    my $item = make_item('UnaryExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok($ti->is_zero($result), 'UnaryExpression with ambiguous_unary still rejected');
}

# PostfixIncDec → type => 'Num'
{
    my $val = make_ctx(type => 'Scalar');
    my $item = make_item('PostfixIncDec', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'PostfixIncDec is valid');
    is(get_tags($result)->{type}, 'Num',
        'PostfixIncDec tags type => Num');
}

# Subscript (array []) → type => 'Scalar'
{
    my $val = make_ctx(type => 'Array');
    my $item = make_item('Subscript', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'Subscript alt 0 is valid');
    is(get_tags($result)->{type}, 'Scalar',
        'Subscript alt 0 (array []) tags type => Scalar');
}

# Subscript (hash {}) → type => 'Scalar'
{
    my $val = make_ctx(type => 'Hash');
    my $item = make_item('Subscript', $val);
    my $result = $ti->on_complete($item, 1, 10);
    is(get_tags($result)->{type}, 'Scalar',
        'Subscript alt 1 (hash {}) tags type => Scalar');
}

# Subscript (deref-call ->()) → type => undef
{
    my $val = make_ctx(type => 'CodeRef');
    my $item = make_item('Subscript', $val);
    my $result = $ti->on_complete($item, 2, 10);
    is(get_tags($result)->{type}, undef,
        'Subscript alt 2 (->()) tags type => undef');
}

# TernaryExpression → type => undef
{
    my $val = make_ctx(type => 'Int');
    my $item = make_item('TernaryExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'TernaryExpression is valid');
    is(get_tags($result)->{type}, undef,
        'TernaryExpression tags type => undef');
}

# AssignmentExpression → type => undef
{
    my $val = make_ctx(type => 'Scalar');
    my $item = make_item('AssignmentExpression', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'AssignmentExpression is valid');
    is(get_tags($result)->{type}, undef,
        'AssignmentExpression tags type => undef');
}

# MethodCall → type => undef
{
    my $val = make_ctx(type => 'Object');
    my $item = make_item('MethodCall', $val);
    my $result = $ti->on_complete($item, 0, 10);
    ok(!$ti->is_zero($result), 'MethodCall is valid');
    is(get_tags($result)->{type}, undef,
        'MethodCall tags type => undef');
}

done_testing;
