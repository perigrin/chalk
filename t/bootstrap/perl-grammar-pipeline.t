# ABOUTME: Phase 0 test — feed 63-rule Perl grammar through existing BNF pipeline.
# ABOUTME: Validates that chalk-bootstrap.bnf parses, produces IR, and generates compilable Perl.
use 5.42.0;
use utf8;
use Test::More;
use Time::HiRes qw(time);

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(
    build_parser parse_ir perl_bnf_text perl_pipeline build_perl_recognizer
);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Optimizer;
use Chalk::Bootstrap::Optimizer::DCE;

# Sanity checks on the BNF file
my $perl_bnf = perl_bnf_text();
ok(length($perl_bnf) > 0, 'BNF file is not empty');
like($perl_bnf, qr/Program ::=/, 'BNF contains Program rule');
like($perl_bnf, qr/Expression ::=/, 'BNF contains Expression rule');

# Phase 0 Gate 1: BNF pipeline accepts chalk-bootstrap.bnf
{
    my $t0 = time();
    my $ir = perl_pipeline();
    my $elapsed = time() - $t0;

    ok(defined $ir, 'Phase 0: BNF pipeline accepts chalk-bootstrap.bnf');

    SKIP: {
        skip 'Parse failed — cannot validate IR', 7 unless defined $ir;

        is(ref($ir), 'ARRAY', 'Phase 0: IR is an arrayref of rules');
        is(scalar($ir->@*), 63, 'Phase 0: IR contains 63 rules');
        diag sprintf("Parse time: %.3f seconds", $elapsed);

        # Phase 0 Gate 2: Code generation produces compilable output
        my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
        my $generated = $target->generate($ir);
        ok(defined $generated, 'Phase 0: code generation produces output');

        # Use a distinct class name for the Perl grammar recognizer
        $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::Generated/g;

        my $t1 = time();
        eval $generated;
        my $gen_elapsed = time() - $t1;
        is($@, '', 'Phase 0: generated Perl recognizer compiles without error');
        diag sprintf("Codegen + eval time: %.3f seconds", $gen_elapsed);

        SKIP: {
            skip 'Generated code failed to compile', 3 if $@;

            # Verify the generated grammar has the expected number of rules
            my $gen_grammar = Chalk::Grammar::Perl::Generated::grammar();
            is(ref($gen_grammar), 'ARRAY', 'Phase 0: generated grammar() returns arrayref');
            is(scalar($gen_grammar->@*), 63, 'Phase 0: generated grammar has 63 rules');

            # Phase 0 Gate 3: Generated recognizer is functional
            # Build a Boolean recognizer from the generated grammar and smoke test
            my $recognizer = build_perl_recognizer($gen_grammar);
            ok(defined $recognizer, 'Phase 0: recognizer built from generated grammar');

            SKIP: {
                skip 'Recognizer not built', 4 unless defined $recognizer;

                # Smoke test: Earley uses first rule as start symbol.
                # The Perl grammar's first rule is _ (optional whitespace),
                # so the recognizer accepts whitespace/comments but not full
                # programs. Start-symbol routing is a Phase 1 concern.
                ok($recognizer->parse(''),
                    'Phase 0: recognizer accepts empty string (start rule is _)');
                ok($recognizer->parse('   '),
                    'Phase 0: recognizer accepts whitespace');
                ok($recognizer->parse('# a comment'),
                    'Phase 0: recognizer accepts comment');

                # Negative test: non-whitespace rejected when start rule is _
                ok(!$recognizer->parse('foo;'),
                    'Phase 0: recognizer rejects non-whitespace (start rule is _)');
            }
        }
    }
}

# Phase 0 Gate 4: Optimized pipeline also works
{
    my $ir = perl_pipeline();

    SKIP: {
        skip 'Parse failed — cannot test optimizer', 3 unless defined $ir;

        my $optimizer = Chalk::Bootstrap::Optimizer->new();
        $optimizer->add_pass(Chalk::Bootstrap::Optimizer::DCE->new());
        my $opt_ir = $optimizer->optimize($ir);

        ok(defined $opt_ir, 'Phase 0: optimized pipeline produces IR');
        is(scalar($opt_ir->@*), 63, 'Phase 0: optimized IR retains 63 rules');

        # Generate and compile optimized version
        my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
        my $generated = $target->generate($opt_ir);
        $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::Optimized/g;
        eval $generated;
        is($@, '', 'Phase 0: optimized Perl recognizer compiles without error');
    }
}

# Phase 0 Gate 5: Desugaring metrics (uses generated grammar, not raw IR)
SKIP: {
    skip 'Generated grammar not available', 2
        unless Chalk::Grammar::Perl::Generated->can('grammar');

    my $gen_grammar = Chalk::Grammar::Perl::Generated::grammar();

    # Count quantifiers in the generated grammar
    my $quantified_count = 0;
    for my $rule ($gen_grammar->@*) {
        for my $alt ($rule->expressions()->@*) {
            for my $sym ($alt->@*) {
                $quantified_count++ if ($sym->quantifier() // '') ne '';
            }
        }
    }

    ok($quantified_count > 0, "Phase 0: grammar has quantified symbols ($quantified_count found)");

    # Desugar and verify expansion
    use Chalk::Bootstrap::Desugar;
    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar($gen_grammar);
    my $expanded = scalar($desugared->@*);
    ok($expanded > 63, "Phase 0: desugaring expands to $expanded rules (from 63)");
    diag "Desugaring: 63 rules + quantifiers -> $expanded effective rules";
}

done_testing();
