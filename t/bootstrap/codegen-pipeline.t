# ABOUTME: Full pipeline integration test for Phase 3 code generation.
# ABOUTME: Parses 10-rule BNF meta-grammar, generates Perl, evals, compares to BNF.pm.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(build_parser parse_ir bnf_text);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Reset factory for clean state

my $parser = build_parser();

# === Test individual rules first to isolate failures ===

# Test: Parse single terminal rule
{
    my $ir = parse_ir($parser, "Identifier ::= /[A-Za-z_][A-Za-z_0-9]*/ ;");
    ok(defined $ir, 'parse Identifier rule');
    is(scalar($ir->@*), 1, 'Identifier: 1 rule');
    is($ir->[0]->inputs()->[0]->value(), 'Identifier', 'Identifier: correct name');
}

# Test: Parse rule with alternatives
{
    my $ir = parse_ir($parser, "Atom ::= Identifier | InlineRegex ;");
    ok(defined $ir, 'parse Atom rule');
    is(scalar($ir->@*), 1, 'Atom: 1 rule');
    my $exprs = $ir->[0]->inputs()->[1];
    is(scalar($exprs->@*), 2, 'Atom: 2 alternatives');
}

# Test: Parse rule with quantifier
{
    my $ir = parse_ir($parser, "Element ::= Atom Quantifier? ;");
    ok(defined $ir, 'parse Element rule');
    is(scalar($ir->@*), 1, 'Element: 1 rule');
}

# Test: Parse Sequence rule with recursive reference
{
    my $ir = parse_ir($parser, "Sequence ::= Element /(?:\\s|#[^\\n]*)+/ Sequence | Element ;");
    ok(defined $ir, 'parse Sequence rule');
    is(scalar($ir->@*), 1, 'Sequence: 1 rule');
    my $exprs = $ir->[0]->inputs()->[1];
    is(scalar($exprs->@*), 2, 'Sequence: 2 alternatives');
}

# === Full 10-rule BNF meta-grammar parse ===

my $ir = parse_ir($parser, bnf_text());
ok(defined $ir, 'full 10-rule BNF parse returns defined IR');

SKIP: {
    skip 'IR parse failed, cannot proceed', 50 unless defined $ir;

    is(ref($ir), 'ARRAY', 'IR is arrayref');
    is(scalar($ir->@*), 10, 'IR contains 10 rules');

    # Verify rule names in order
    my @expected_names = qw(Grammar Rule Alternatives Sequence Element Atom Quantifier Comment Identifier InlineRegex);
    for my $i (0 .. $#expected_names) {
        my $rule = $ir->[$i];
        is($rule->inputs()->[0]->value(), $expected_names[$i], "rule $i is $expected_names[$i]");
    }

    # === Code Generation ===

    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated_code = $target->generate($ir);

    ok(defined $generated_code, 'generate() returns defined output');
    like($generated_code, qr/class Chalk::Grammar::BNF::Generated/, 'generated code contains class');

    # eval the generated code
    eval $generated_code;
    is($@, '', 'generated code evals without error') or diag("Eval error: $@\nGenerated code:\n$generated_code");

    SKIP: {
        skip 'eval failed, cannot compare', 30 if $@;

        # Call generated grammar
        my $generated_grammar = Chalk::Grammar::BNF::Generated::grammar();
        isa_ok($generated_grammar, 'ARRAY', 'generated grammar is arrayref');

        # Compare against hand-written BNF.pm
        my $reference_grammar = Chalk::Grammar::BNF::grammar();

        is(scalar($generated_grammar->@*), scalar($reference_grammar->@*),
            'same number of rules');

        # Compare each rule structurally
        for my $i (0 .. $#{$reference_grammar}) {
            my $gen = $generated_grammar->[$i];
            my $ref = $reference_grammar->[$i];

            is($gen->name(), $ref->name(), "rule $i: name matches (${\$ref->name()})");
            is($gen->alternative_count(), $ref->alternative_count(),
                "rule $i (${\$ref->name()}): same number of alternatives");

            # Compare each alternative
            for my $j (0 .. $#{$ref->expressions()}) {
                my $gen_alt = $gen->expressions()->[$j];
                my $ref_alt = $ref->expressions()->[$j];

                is(scalar($gen_alt->@*), scalar($ref_alt->@*),
                    "rule $i (${\$ref->name()}) alt $j: same number of symbols");

                for my $k (0 .. $#{$ref_alt}) {
                    my $gs = $gen_alt->[$k];
                    my $rs = $ref_alt->[$k];

                    is($gs->type(), $rs->type(),
                        "rule $i (${\$ref->name()}) alt $j sym $k: type matches");
                    is($gs->value(), $rs->value(),
                        "rule $i (${\$ref->name()}) alt $j sym $k: value matches");

                    my $gs_q = $gs->quantifier() // 'undef';
                    my $rs_q = $rs->quantifier() // 'undef';
                    is($gs_q, $rs_q,
                        "rule $i (${\$ref->name()}) alt $j sym $k: quantifier matches");
                }
            }
        }
    }
}

# === Gap 3.1: Test that Generated.pm on disk matches pipeline output ===

{
    my $ir = parse_ir($parser, bnf_text());
    ok(defined $ir, 'parse BNF for disk sync test');

    SKIP: {
        skip 'IR parse failed, cannot test disk sync', 2 unless defined $ir;

        my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
        my $generated_code = $target->generate($ir);

        ok(defined $generated_code, 'generated code from pipeline');

        # Read Generated.pm from disk
        my $generated_pm_path = 'lib/Chalk/Grammar/BNF/Generated.pm';
        my $disk_content = do {
            open my $fh, '<', $generated_pm_path
                or die "Cannot read $generated_pm_path: $!";
            local $/;
            <$fh>;
        };

        is($generated_code, $disk_content,
            'Generated.pm on disk matches pipeline output (byte-identical)');
    }
}

done_testing();
