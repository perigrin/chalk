# ABOUTME: Verifies that code generation produces byte-identical output across runs.
# ABOUTME: Tests determinism by generating the same IR twice and comparing results.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Composite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Grammar::BNF::Actions;
use Chalk::Bootstrap::Desugar qw(desugar_grammar);
use Chalk::Grammar::BNF;
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;

sub build_and_generate {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $grammar = Chalk::Grammar::BNF::grammar();
    my $desugared = desugar_grammar($grammar);

    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $actions = Chalk::Grammar::BNF::Actions->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    my $comp_sr = Chalk::Bootstrap::Semiring::Composite->new(
        boolean  => $bool_sr,
        semantic => $sem_sr,
    );

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $comp_sr,
    );

    my $bnf_text = <<'BNF';
Grammar ::= /(?:\s|#[^\n]*)*/ Rule+ ;
Rule ::= Identifier /(?:\s|#[^\n]*)*/ /::=/ /(?:\s|#[^\n]*)*/ Alternatives /(?:\s|#[^\n]*)*/ /;/ /(?:\s|#[^\n]*)*/ ;
Alternatives ::= Sequence /(?:\s|#[^\n]*)*/ /\|/ /(?:\s|#[^\n]*)*/ Alternatives | Sequence ;
Sequence ::= Element /(?:\s|#[^\n]*)+/ Sequence | Element ;
Element ::= Atom Quantifier? ;
Atom ::= Identifier | InlineRegex ;
Quantifier ::= /\*/ | /\+/ | /\?/ ;
Comment ::= /#[^\n]*/ ;
Identifier ::= /[A-Za-z_][A-Za-z_0-9]*/ ;
InlineRegex ::= /\/(?:[^\/\\]|\\.)*\// ;
BNF

    my $result = $parser->parse_value($bnf_text);
    return undef unless defined $result;
    my ($bool_val, $context) = $result->@*;
    return undef unless $bool_val;
    my $ir = $context->extract();

    my $target = Chalk::Bootstrap::Target::Perl->new();
    return $target->generate($ir);
}

# Generate twice and compare
my $output1 = build_and_generate();
ok(defined $output1, 'first generation succeeds');

my $output2 = build_and_generate();
ok(defined $output2, 'second generation succeeds');

is($output1, $output2, 'two generations produce byte-identical output');

# Verify non-empty
ok(length($output1) > 100, 'generated output is non-trivial');

# Verify it contains expected content
like($output1, qr/10.*rule|Grammar.*InlineRegex/s, 'output contains expected rules');

done_testing();
