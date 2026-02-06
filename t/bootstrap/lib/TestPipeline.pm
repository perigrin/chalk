# ABOUTME: Shared test utilities for building the full Earley + semantic action pipeline.
# ABOUTME: Exports helpers to construct parser, parse BNF text, and extract IR for testing.
use 5.42.0;
use utf8;

package TestPipeline;

use Exporter 'import';
our @EXPORT_OK = qw(build_parser parse_ir bnf_text full_pipeline optimized_pipeline);

use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Composite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Grammar::BNF::Actions;
use Chalk::Bootstrap::Desugar qw(desugar_grammar);
use Chalk::Grammar::BNF;
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Optimizer;
use Chalk::Bootstrap::Optimizer::DCE;

# Returns the canonical 10-rule BNF meta-grammar as a string
sub bnf_text {
    return <<'BNF';
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
}

# Builds the full Earley parser with composite semiring and desugared BNF grammar
sub build_parser {
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

    return Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $comp_sr,
    );
}

# Parses input and extracts the IR (semantic value)
# Returns undef if parse fails
sub parse_ir {
    my ($parser, $input) = @_;
    my $result = $parser->parse_value($input);
    return undef unless defined $result;
    my ($bool_val, $context) = $result->@*;
    return undef unless $bool_val;
    return $context->extract();
}

# Convenience function: resets factory, builds parser, parses BNF text, returns IR
sub full_pipeline {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_parser();
    return parse_ir($parser, bnf_text());
}

# Convenience function: full pipeline + DCE optimization
sub optimized_pipeline {
    my $ir = full_pipeline();
    return undef unless defined $ir;

    my $optimizer = Chalk::Bootstrap::Optimizer->new();
    $optimizer->add_pass(Chalk::Bootstrap::Optimizer::DCE->new());
    return $optimizer->optimize($ir);
}

1;
