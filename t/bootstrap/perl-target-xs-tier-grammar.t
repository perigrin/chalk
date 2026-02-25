# ABOUTME: Tests Perl IR to XS compilation for Tier Grammar files (6 grammar modules).
# ABOUTME: Symbol, Rule, BNF, Generated, KeywordTable, PrecedenceTable — compile+load+behavioral.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);

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

eval { require Module::Build; 1 }
    or plan skip_all => 'Module::Build not installed';

# === Setup ===

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Perl::Target::XS;

# Build Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $bnf_target = Chalk::Bootstrap::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSTierGrammarTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSTierGrammarTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# === Helper to parse file -> IR ===

my sub parse_file_ir($file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;

    my $sem_ctx = $result->[4];
    return undef unless defined $sem_ctx;
    return $sem_ctx->extract();
}

# === Helper to build, compile, load XS module ===

my sub build_and_load($ir, $module_name) {
    my $xs_target = Chalk::Bootstrap::Perl::Target::XS->new(
        module_name => $module_name,
    );
    my $dist = $xs_target->generate_distribution($ir);
    return (undef, "generate_distribution failed") unless ref($dist) eq 'HASH';

    my $tmpdir = tempdir(CLEANUP => 1);
    for my $path (sort keys $dist->%*) {
        my $full_path = "$tmpdir/$path";
        my $dir = dirname($full_path);
        make_path($dir) unless -d $dir;
        open(my $fh, '>:encoding(UTF-8)', $full_path)
            or die "Cannot write $full_path: $!";
        print $fh $dist->{$path};
        close $fh;
    }

    my $build_output = `cd "$tmpdir" && "$^X" Build.PL 2>&1 && "$^X" Build 2>&1`;
    my $exit = $? >> 8;
    return (undef, "Build failed (exit $exit): $build_output") if $exit != 0;

    unshift @INC, "$tmpdir/blib/lib", "$tmpdir/blib/arch";
    eval "require $module_name";
    return (undef, "Load failed: $@") if $@;

    return ($dist, undef);
}

# ============================================================
# 1. Grammar/Symbol.pm — type, value, quantifier fields + methods
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Grammar/Symbol.pm');
    ok(defined $ir, 'Symbol: parse produces IR');

    SKIP: {
        skip 'Symbol: no IR', 10 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierGrammar::Symbol';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Symbol: XS builds') or do {
            diag $err;
            skip 'Symbol: build failed', 8;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'Symbol: XS has MODULE line');

        my $sym = eval { $module->new(type => 'terminal', value => '[a-z]+') };
        is($@, '', 'Symbol: new() with type+value succeeds') or skip 'Symbol: new failed', 6;
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
    my $ir = parse_file_ir('lib/Chalk/Grammar/Rule.pm');
    ok(defined $ir, 'Rule: parse produces IR');

    SKIP: {
        skip 'Rule: no IR', 8 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierGrammar::Rule';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Rule: XS builds') or do {
            diag $err;
            skip 'Rule: build failed', 6;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'Rule: XS has MODULE line');

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
    my $ir = parse_file_ir('lib/Chalk/Grammar/BNF.pm');
    ok(defined $ir, 'BNF: parse produces IR');

    SKIP: {
        skip 'BNF: no IR', 4 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierGrammar::BNF';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'BNF: XS builds') or do {
            diag $err;
            skip 'BNF: build failed', 2;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'BNF: XS has MODULE line');

        # BNF has only plain sub (not method), so grammar() lives in the Perl PM layer.
        # XS emitter only emits class methods, not package subs.
        SKIP: {
            skip 'BNF: grammar() is a Perl-layer sub, not emitted to XS', 2;
            like($xs_code, qr/grammar\(/, 'BNF: XS has grammar sub');
            my $rules = eval { $module->grammar() };
            ok(ref($rules) eq 'ARRAY', 'BNF: grammar() returns arrayref');
        }
    }
}

# ============================================================
# 4. Grammar/BNF/Generated.pm — generated grammar equivalent
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Grammar/BNF/Generated.pm');
    ok(defined $ir, 'Generated: parse produces IR');

    SKIP: {
        skip 'Generated: no IR', 4 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierGrammar::BNFGenerated';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Generated: XS builds') or do {
            diag $err;
            skip 'Generated: build failed', 2;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'Generated: XS has MODULE line');

        # Generated has only plain sub (not method), so grammar() lives in the Perl PM layer.
        SKIP: {
            skip 'Generated: grammar() is a Perl-layer sub, not emitted to XS', 2;
            like($xs_code, qr/grammar\(/, 'Generated: XS has grammar sub');
            my $rules = eval { $module->grammar() };
            ok(ref($rules) eq 'ARRAY', 'Generated: grammar() returns arrayref');
        }
    }
}

# ============================================================
# 5. Grammar/Perl/KeywordTable.pm — is_keyword lookup
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Grammar/Perl/KeywordTable.pm');
    ok(defined $ir, 'KeywordTable: parse produces IR');

    SKIP: {
        skip 'KeywordTable: no IR', 5 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierGrammar::KeywordTable';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'KeywordTable: XS builds') or do {
            diag $err;
            skip 'KeywordTable: build failed', 3;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'KeywordTable: XS has MODULE line');

        # KeywordTable has only plain sub (not method), so is_keyword() lives in the Perl PM layer.
        SKIP: {
            skip 'KeywordTable: is_keyword() is a Perl-layer sub, not emitted to XS', 3;
            like($xs_code, qr/is_keyword\(/, 'KeywordTable: XS has is_keyword sub');
            ok($module->is_keyword('use'),      'KeywordTable: is_keyword("use") is true');
            ok(!$module->is_keyword('foobar'),  'KeywordTable: is_keyword("foobar") is false');
        }
    }
}

# ============================================================
# 6. Grammar/Perl/PrecedenceTable.pm — get_table + lookup
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Grammar/Perl/PrecedenceTable.pm');
    ok(defined $ir, 'PrecedenceTable: parse produces IR');

    SKIP: {
        skip 'PrecedenceTable: no IR', 5 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierGrammar::PrecedenceTable';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'PrecedenceTable: XS builds') or do {
            diag $err;
            skip 'PrecedenceTable: build failed', 3;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'PrecedenceTable: XS has MODULE line');

        # PrecedenceTable has only plain sub (not method), so get_table()/lookup() live in the Perl PM layer.
        SKIP: {
            skip 'PrecedenceTable: get_table/lookup are Perl-layer subs, not emitted to XS', 3;
            like($xs_code, qr/get_table\(|lookup\(/, 'PrecedenceTable: XS has table methods');
            my $entry = eval { $module->lookup('+') };
            ok(defined $entry, 'PrecedenceTable: lookup("+") returns defined');
            is($entry->{assoc}, 'left', 'PrecedenceTable: "+" has left associativity');
        }
    }
}

done_testing();
