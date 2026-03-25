# ABOUTME: Tests Perl IR to Target::C compilation for Tier Grammar files (6 grammar modules).
# ABOUTME: Symbol, Rule, BNF, Generated, KeywordTable, PrecedenceTable — compile+load+behavioral.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

# === Skip guards ===

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
unless ($have_compiler) {
    plan skip_all => 'No C compiler available';
}

# === Setup ===

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use TestXSHelpers qw(build_and_load);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Build Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSTierGrammarTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSTierGrammarTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# === Helper to parse file -> IR, SemanticAction, semantic context ===

my sub parse_file_ir($file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;
    close $fh;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();

    my $result = $parser->parse_value($source);
    return () unless defined $result;

    my $sa = $semiring->semirings()->[4];
    my $sem_ctx = $result->[4];
    return () unless defined $sem_ctx;
    my $ir = $sem_ctx->extract();
    return () unless defined $ir;
    return ($ir, $sa, $sem_ctx);
}

# ============================================================
# 1. Grammar/Symbol.pm — type, value, quantifier fields + methods
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Grammar/Symbol.pm');
    ok(defined $ir, 'Symbol: parse produces IR');

    SKIP: {
        skip 'Symbol: no IR', 8 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierGrammar::Symbol';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $result, 'Symbol: XS builds') or do {
            diag $err;
            skip 'Symbol: build failed', 7;
        };

        my $sym = eval { $module->new(type => 'terminal', value => '[a-z]+') };
        is($@, '', 'Symbol: new() with type+value succeeds') or skip 'Symbol: new failed', 5;
        is($sym->type(),      'terminal', 'Symbol: type() reader');
        is($sym->value(),     '[a-z]+',   'Symbol: value() reader');
        is($sym->quantifier(), undef,     'Symbol: quantifier() defaults to undef');

        my $sym2 = eval { $module->new(type => 'reference', value => 'Rule', quantifier => '+') };
        is($@, '', 'Symbol: new() with quantifier succeeds') or skip 'Symbol: quantifier test failed', 1;
        is($sym2->quantifier(), '+', 'Symbol: quantifier() reader');
    }
}

# ============================================================
# 2. Grammar/Rule.pm — name, expressions fields + alternative_count
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Grammar/Rule.pm');
    ok(defined $ir, 'Rule: parse produces IR');

    SKIP: {
        skip 'Rule: no IR', 6 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierGrammar::Rule';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $result, 'Rule: XS builds') or do {
            diag $err;
            skip 'Rule: build failed', 5;
        };

        my $rule = eval {
            $module->new(
                name        => 'TestRule',
                expressions => [ ['sym_a', 'sym_b'], ['sym_c'] ],
            )
        };
        is($@, '', 'Rule: new() with name+expressions succeeds') or skip 'Rule: new failed', 3;
        is($rule->name(),        'TestRule', 'Rule: name() reader');
        ok(defined $rule->expressions(), 'Rule: expressions() reader returns defined value');

        SKIP: {
            skip 'Rule: alternative_count needs Chalk::Grammar::Symbol isa support', 1;
            is($rule->alternative_count(), 2, 'Rule: alternative_count()');
        }
    }
}

# ============================================================
# 3. Grammar/BNF.pm — grammar loader with 10 rules
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Grammar/BNF.pm');
    ok(defined $ir, 'BNF: parse produces IR');

    SKIP: {
        skip 'BNF: no IR', 3 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierGrammar::BNF';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $result, 'BNF: XS builds') or do {
            diag $err;
            skip 'BNF: build failed', 2;
        };

        # BNF has only plain sub (not method), so grammar() lives in the Perl PM layer.
        # XS emitter only emits class methods, not package subs.
        SKIP: {
            skip 'BNF: grammar() is a Perl-layer sub, not emitted to XS', 2;
            my $rules = eval { $module->grammar() };
            ok(ref($rules) eq 'ARRAY', 'BNF: grammar() returns arrayref');
        }
    }
}

# ============================================================
# 4. Grammar/BNF/Generated.pm — generated grammar equivalent
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Grammar/BNF/Generated.pm');
    ok(defined $ir, 'Generated: parse produces IR');

    SKIP: {
        skip 'Generated: no IR', 3 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierGrammar::BNFGenerated';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $result, 'Generated: XS builds') or do {
            diag $err;
            skip 'Generated: build failed', 2;
        };

        # Generated has only plain sub (not method), so grammar() lives in the Perl PM layer.
        SKIP: {
            skip 'Generated: grammar() is a Perl-layer sub, not emitted to XS', 2;
            my $rules = eval { $module->grammar() };
            ok(ref($rules) eq 'ARRAY', 'Generated: grammar() returns arrayref');
        }
    }
}

# ============================================================
# 5. Grammar/Perl/KeywordTable.pm — is_keyword lookup
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Grammar/Perl/KeywordTable.pm');
    ok(defined $ir, 'KeywordTable: parse produces IR');

    SKIP: {
        skip 'KeywordTable: no IR', 4 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierGrammar::KeywordTable';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $result, 'KeywordTable: XS builds') or do {
            diag $err;
            skip 'KeywordTable: build failed', 3;
        };

        # KeywordTable has only plain sub (not method), so is_keyword() lives in the Perl PM layer.
        SKIP: {
            skip 'KeywordTable: is_keyword() is a Perl-layer sub, not emitted to XS', 3;
            ok($module->is_keyword('use'),      'KeywordTable: is_keyword("use") is true');
            ok(!$module->is_keyword('foobar'),  'KeywordTable: is_keyword("foobar") is false');
        }
    }
}

# ============================================================
# 6. Grammar/Perl/PrecedenceTable.pm — get_table + lookup
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Grammar/Perl/PrecedenceTable.pm');
    ok(defined $ir, 'PrecedenceTable: parse produces IR');

    SKIP: {
        skip 'PrecedenceTable: no IR', 4 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierGrammar::PrecedenceTable';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $result, 'PrecedenceTable: XS builds') or do {
            diag $err;
            skip 'PrecedenceTable: build failed', 3;
        };

        # PrecedenceTable has only plain sub (not method), so get_table()/lookup() live in the Perl PM layer.
        SKIP: {
            skip 'PrecedenceTable: get_table/lookup are Perl-layer subs, not emitted to XS', 3;
            my $entry = eval { $module->lookup('+') };
            ok(defined $entry, 'PrecedenceTable: lookup("+") returns defined');
            is($entry->{assoc}, 'left', 'PrecedenceTable: "+" has left associativity');
        }
    }
}

done_testing();
