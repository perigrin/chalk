# ABOUTME: Tests for Structural semiring that disambiguates Block vs HashConstructor.
# ABOUTME: Covers basic ops, tagging, boundary resets, add() preference, and parser integration.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

# ========================================================================
# Phase 1: Basic semiring operations (zero, one, is_zero, multiply, add)
# ========================================================================
use_ok('Chalk::Bootstrap::Semiring::Structural');

my $sr = Chalk::Bootstrap::Semiring::Structural->new();

# --- zero / one / is_zero ---
{
    my $z = $sr->zero();
    ok($sr->is_zero($z), 'zero is zero');

    my $o = $sr->one();
    ok(!$sr->is_zero($o), 'one is not zero');

    ok($o->{valid}, 'one has valid => true');
    ok(!$z->{valid}, 'zero has valid => false');
}

# --- multiply: zero propagation ---
{
    my $z = $sr->zero();
    my $o = $sr->one();

    ok($sr->is_zero($sr->multiply($z, $o)), 'zero * one = zero');
    ok($sr->is_zero($sr->multiply($o, $z)), 'one * zero = zero');
    ok($sr->is_zero($sr->multiply($z, $z)), 'zero * zero = zero');
    ok(!$sr->is_zero($sr->multiply($o, $o)), 'one * one is not zero');
}

# --- multiply: tag propagation ---
{
    my $block_val = { valid => true, is_block => true };
    my $hash_val  = { valid => true, is_hash  => true };
    my $plain     = $sr->one();

    my $r1 = $sr->multiply($block_val, $plain);
    ok($r1->{is_block}, 'block tag propagates from left through multiply');

    my $r2 = $sr->multiply($plain, $hash_val);
    ok($r2->{is_hash}, 'hash tag propagates from right through multiply');

    my $r3 = $sr->multiply($block_val, $hash_val);
    ok($r3->{is_block}, 'both tags: block propagates through multiply');
    ok($r3->{is_hash}, 'both tags: hash propagates through multiply');
}

# --- add: first non-zero when one is zero ---
{
    my $z = $sr->zero();
    my $o = $sr->one();

    my $r1 = $sr->add($z, $o);
    ok(!$sr->is_zero($r1), 'add(zero, one) = non-zero');

    my $r2 = $sr->add($o, $z);
    ok(!$sr->is_zero($r2), 'add(one, zero) = non-zero');

    ok($sr->is_zero($sr->add($z, $z)), 'add(zero, zero) = zero');
}

# --- add: prefer is_block over is_hash ---
{
    my $block_val = { valid => true, is_block => true };
    my $hash_val  = { valid => true, is_hash  => true };

    my $r1 = $sr->add($block_val, $hash_val);
    ok($r1->{is_block}, 'add(block, hash) prefers block');
    ok(!$r1->{is_hash}, 'add(block, hash) does not carry hash tag');

    my $r2 = $sr->add($hash_val, $block_val);
    ok($r2->{is_block}, 'add(hash, block) still prefers block');
    ok(!$r2->{is_hash}, 'add(hash, block) does not carry hash tag');
}

# --- add: both valid, neither tagged ---
{
    my $o1 = $sr->one();
    my $o2 = $sr->one();

    my $r = $sr->add($o1, $o2);
    ok(!$sr->is_zero($r), 'add(one, one) is not zero');
    ok($r->{valid}, 'add(one, one) is valid');
}

# ========================================================================
# Phase 2: on_scan (transparency)
# ========================================================================

# Mock item for on_scan/on_complete testing
my sub mock_item($rule_name, $value) {
    return {
        rule  => bless({ _name => $rule_name }, 'MockRule'),
        value => $value,
    };
}

# Provide a name() method for MockRule
{
    package MockRule;
    sub name { return $_[0]->{_name} }
}

{
    my $o = $sr->one();
    my $item = mock_item('Identifier', $o);
    my $r = $sr->on_scan($item, 0, 0, 'foo');
    ok(!$sr->is_zero($r), 'on_scan is transparent for Identifier');
    ok($r->{valid}, 'on_scan result is valid');
}

{
    my $z = $sr->zero();
    my $item = mock_item('Identifier', $z);
    my $r = $sr->on_scan($item, 0, 0, 'foo');
    ok($sr->is_zero($r), 'on_scan propagates zero');
}

{
    my $block_val = { valid => true, is_block => true };
    my $item = mock_item('Block', $block_val);
    my $r = $sr->on_scan($item, 0, 0, '{');
    ok($r->{is_block}, 'on_scan preserves block tag through multiply');
}

# ========================================================================
# Phase 3: on_complete (tagging and boundary clearing)
# ========================================================================

# --- Block completion → is_block tag ---
{
    my $o = $sr->one();
    my $item = mock_item('Block', $o);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'Block completion is valid');
    ok($r->{is_block}, 'Block completion sets is_block tag');
    ok(!$r->{is_hash}, 'Block completion does not set is_hash');
}

# --- HashConstructor completion → is_hash tag ---
{
    my $o = $sr->one();
    my $item = mock_item('HashConstructor', $o);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'HashConstructor completion is valid');
    ok($r->{is_hash}, 'HashConstructor completion sets is_hash tag');
    ok(!$r->{is_block}, 'HashConstructor completion does not set is_block');
}

# --- Boundary rules clear tags ---
for my $boundary_rule (qw(ParenExpr ArrayConstructor Program StatementList)) {
    my $tagged = { valid => true, is_block => true, is_hash => true };
    my $item = mock_item($boundary_rule, $tagged);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), "$boundary_rule completion is valid");
    ok(!$r->{is_block}, "$boundary_rule clears is_block tag");
    ok(!$r->{is_hash}, "$boundary_rule clears is_hash tag");
}

# --- Other rules pass through ---
{
    my $block_val = { valid => true, is_block => true };
    my $item = mock_item('Expression', $block_val);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'Expression completion is valid');
    ok($r->{is_block}, 'Expression passes through is_block tag');
}

{
    my $hash_val = { valid => true, is_hash => true };
    my $item = mock_item('Atom', $hash_val);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'Atom completion is valid');
    ok($r->{is_hash}, 'Atom passes through is_hash tag');
}

# --- Zero propagation ---
{
    my $z = $sr->zero();
    my $item = mock_item('Block', $z);
    my $r = $sr->on_complete($item, 0, 0);
    ok($sr->is_zero($r), 'on_complete propagates zero');
}

# --- StatementItem: bare (alt_idx 1) sets is_bare_statement ---
{
    my $o = $sr->one();
    my $item = mock_item('StatementItem', $o);

    # alt_idx 0 = SimpleStatement ";" — NOT bare
    my $r0 = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r0), 'StatementItem alt 0 (with semicolon) is valid');
    ok(!$r0->{is_bare_statement}, 'StatementItem alt 0 does NOT set is_bare_statement');

    # alt_idx 1 = SimpleStatement (no semicolon) — bare
    my $r1 = $sr->on_complete($item, 1, 0);
    ok(!$sr->is_zero($r1), 'StatementItem alt 1 (bare) is valid');
    ok($r1->{is_bare_statement}, 'StatementItem alt 1 sets is_bare_statement');

    # alt_idx 2 = CompoundStatement — NOT bare
    my $r2 = $sr->on_complete($item, 2, 0);
    ok(!$sr->is_zero($r2), 'StatementItem alt 2 (compound) is valid');
    ok(!$r2->{is_bare_statement}, 'StatementItem alt 2 does NOT set is_bare_statement');
}

# --- multiply: is_bare_statement propagation ---
{
    my $bare = { valid => true, is_bare_statement => true };
    my $plain = $sr->one();

    my $r1 = $sr->multiply($bare, $plain);
    ok($r1->{is_bare_statement}, 'is_bare_statement propagates from left through multiply');

    my $r2 = $sr->multiply($plain, $bare);
    ok($r2->{is_bare_statement}, 'is_bare_statement propagates from right through multiply');
}

# --- add: prefer non-bare over bare ---
{
    my $bare = { valid => true, is_bare_statement => true };
    my $non_bare = { valid => true };

    my $r1 = $sr->add($bare, $non_bare);
    ok(!$r1->{is_bare_statement}, 'add(bare, non-bare) prefers non-bare');
    ok($r1->{valid}, 'add(bare, non-bare) is valid');

    my $r2 = $sr->add($non_bare, $bare);
    ok(!$r2->{is_bare_statement}, 'add(non-bare, bare) prefers non-bare');
    ok($r2->{valid}, 'add(non-bare, bare) is valid');
}

# --- add: both bare → stays bare ---
{
    my $bare1 = { valid => true, is_bare_statement => true };
    my $bare2 = { valid => true, is_bare_statement => true };

    my $r = $sr->add($bare1, $bare2);
    ok($r->{is_bare_statement}, 'add(bare, bare) stays bare');
}

# --- Block clears is_bare_statement (last stmt in block is legitimately bare) ---
{
    my $bare = { valid => true, is_bare_statement => true };
    my $item = mock_item('Block', $bare);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'Block with bare content is valid');
    ok($r->{is_block}, 'Block completion still sets is_block');
    ok(!$r->{is_bare_statement}, 'Block clears is_bare_statement');
}

# --- Program preserves is_bare_statement (needed for alternative selection) ---
{
    my $bare = { valid => true, is_bare_statement => true };
    my $item = mock_item('Program', $bare);
    my $r = $sr->on_complete($item, 0, 0);
    ok($r->{is_bare_statement},
        'Program preserves is_bare_statement for alternative selection');
}

# --- StatementList preserves is_bare_statement ---
{
    my $bare = { valid => true, is_bare_statement => true };
    my $item = mock_item('StatementList', $bare);

    my $r0 = $sr->on_complete($item, 0, 0);
    ok($r0->{is_bare_statement},
        'StatementList alt 0 preserves is_bare_statement');
    ok(!$r0->{is_block}, 'StatementList still clears is_block');
    ok(!$r0->{is_hash}, 'StatementList still clears is_hash');
}

# --- StatementList without bare has no bare tag ---
{
    my $o = $sr->one();
    my $item = mock_item('StatementList', $o);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$r->{is_bare_statement},
        'StatementList without bare does not set is_bare_statement');
}

# --- StatementList alt 1 with is_bare_statement is still valid ---
# (bare-preference disambiguation happens via add(), not on_complete zeroing)
{
    my $bare_only = { valid => true, is_bare_statement => true };
    my $item = mock_item('StatementList', $bare_only);
    my $r = $sr->on_complete($item, 1, 0);
    ok(!$sr->is_zero($r),
        'StatementList alt 1 with is_bare_statement is valid');

    my $o = $sr->one();
    my $item2 = mock_item('StatementList', $o);
    my $r2 = $sr->on_complete($item2, 1, 0);
    ok(!$sr->is_zero($r2),
        'StatementList alt 1 without any bare tags is valid');
}

# ========================================================================
# Phase 4: Integration with full Earley parser
# Uses Bool+Structural only to isolate the Structural semiring's behavior
# from pre-existing nondeterminism in Precedence/TypeInference add().
# ========================================================================
use TestPipeline qw(perl_pipeline);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Composite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::Structural;
use Chalk::Bootstrap::Desugar;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 15 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::StructuralInteg/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 15 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::StructuralInteg::grammar();
    my @reordered;
    my $found = false;
    for my $rule ($gen_grammar->@*) {
        if (!$found && $rule->name() eq 'Program') {
            unshift @reordered, $rule;
            $found = true;
        } else {
            push @reordered, $rule;
        }
    }
    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar(\@reordered);

    # 2-ary composite: Bool + Structural (no Prec/TypeInf/Semantic)
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();

    my $comp_sr = Chalk::Bootstrap::Semiring::Composite->new(
        semirings => [$bool_sr, $struct_sr],
    );

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $comp_sr,
    );

    # Helper: parse and return result tuple [0]=Boolean, [1]=Structural
    my sub parse_result($source) {
        return $parser->parse_value($source);
    }

    # Helper: extract Structural value from result
    my sub struct_val($result) {
        return $result->[1] if defined $result;
        return undef;
    }

    # --- { 42 } at statement level: ambiguous, should prefer Block ---
    {
        my $result = parse_result('{ 42 }');
        ok(defined $result, '{ 42 } parses at statement level');
        my $sv = struct_val($result);
        ok($sv->{valid}, '{ 42 } structural value is valid');
        # At statement level, Block should be preferred
        ok($sv->{is_block} || !$sv->{is_hash},
            '{ 42 } at statement level: block preferred or hash not tagged');
    }

    # --- { } at statement level: ambiguous, should prefer Block ---
    {
        my $result = parse_result('{ }');
        ok(defined $result, '{ } parses at statement level');
        my $sv = struct_val($result);
        ok($sv->{valid}, '{ } structural value is valid');
        ok($sv->{is_block} || !$sv->{is_hash},
            '{ } at statement level: block preferred or hash not tagged');
    }

    # --- { $x => $y } : naturally unambiguous → HashConstructor ---
    {
        my $result = parse_result('my $h = { $x => $y };');
        ok(defined $result, '{ $x => $y } in assignment parses');
    }

    # --- { my $x = 42; } : semicolon makes it unambiguous Block ---
    {
        my $result = parse_result('{ my $x = 42; }');
        ok(defined $result, '{ my $x = 42; } parses');
    }

    # --- Simple non-brace programs still work ---
    {
        my $result = parse_result('my $x = 42;');
        ok(defined $result, 'simple declaration still parses');
        my $sv = struct_val($result);
        ok($sv->{valid}, 'simple declaration structural value is valid');
        # No block or hash tags for non-brace content (Program clears them)
        ok(!$sv->{is_block} && !$sv->{is_hash},
            'simple declaration has no block/hash tags');
    }

    # --- Multiple statements with blocks ---
    {
        my $result = parse_result('my $x = 1; { my $y = 2; }');
        ok(defined $result, 'statement + block parses');
    }

    # --- Sub with block body ---
    {
        my $result = parse_result('sub foo { }');
        ok(defined $result, 'sub with empty block parses');
    }

    # --- if/while with blocks (control flow) ---
    {
        my $result = parse_result('if ($x) { my $y = 1; }');
        ok(defined $result, 'if with block body parses');
    }

    {
        my $result = parse_result('while ($x) { my $y = 1; }');
        ok(defined $result, 'while with block body parses');
    }

    # --- Expression separator disambiguation ---
    # These test that ambiguous operators (+, -, //) are parsed as binary
    # operators rather than starting a new unseparated statement.

    # Binary + should not be split into bare $a + unary +$b
    {
        my $result = parse_result('my $a = 1; my $c = $a + 3;');
        ok(defined $result, 'binary + in assignment parses');
    }

    # Binary - should not be split into bare $a + unary -$b
    {
        my $result = parse_result('my $a = 1; my $c = $a - 3;');
        ok(defined $result, 'binary - in assignment parses');
    }

    # // (defined-or) should not be parsed as empty regex literal
    {
        my $result = parse_result('my $a = 0; my $b = $a // 1;');
        ok(defined $result, 'defined-or (//) in assignment parses');
    }

    # //= (compound defined-or assign)
    {
        my $result = parse_result('my $a = 0; $a //= 1;');
        ok(defined $result, 'compound //= parses');
    }

    # Last statement in block without semicolon is legitimate
    {
        my $result = parse_result('{ my $x = 42 }');
        ok(defined $result, 'bare last statement in block parses');
    }

    # Last statement at end of program without semicolon
    {
        my $result = parse_result('my $x = 42');
        ok(defined $result, 'bare last statement at EOF parses');
    }

    # Multiple statements where last is bare (legitimate)
    {
        my $result = parse_result('my $x = 1; my $y = $x + 2');
        ok(defined $result, 'separated statements with bare final parses');
    }
}

done_testing();
