# ABOUTME: Shared test utilities for building the full Earley + semantic action pipeline.
# ABOUTME: Exports helpers to construct parser, parse BNF text, and extract IR for testing.
use 5.42.0;
use utf8;

package TestPipeline;

use Exporter 'import';
our @EXPORT_OK = qw(
    build_parser parse_ir bnf_text full_pipeline optimized_pipeline grammars_match
    perl_bnf_text perl_pipeline build_perl_recognizer build_perl_concise_parser
    build_perl_ir_parser
);

use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Grammar::BNF::Actions;
use Chalk::Bootstrap::Desugar;
use Chalk::Grammar::BNF;
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Optimizer;
use Chalk::Bootstrap::Optimizer::DCE;
use Chalk::Bootstrap::ConciseTree::Actions;
use Chalk::Bootstrap::Semiring::Precedence;
use Chalk::Bootstrap::Semiring::TypeInference;
use Chalk::Grammar::Perl::PrecedenceTable;
use Chalk::Grammar::Perl::KeywordTable;
use Chalk::Grammar::Perl::TypeLibrary;
use Chalk::Bootstrap::Semiring::Structural;
use Chalk::Bootstrap::Perl::Actions;

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
    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar($grammar);

    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $actions = Chalk::Grammar::BNF::Actions->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    my $comp_sr = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
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

# Convenience function: full pipeline returning grammar data.
# Grammar::Rule objects are direct data model objects, not IR nodes,
# so no IR optimizer passes apply to them.
sub optimized_pipeline {
    return full_pipeline();
}

# Returns the 65-rule Perl grammar as BNF text (reads from docs/chalk-bootstrap.bnf)
sub perl_bnf_text {
    my $bnf_file = 'docs/chalk-bootstrap.bnf';
    open my $fh, '<:utf8', $bnf_file or die "Cannot read $bnf_file: $!";
    local $/;
    return <$fh>;
}

# Convenience function: resets factory, builds parser, parses Perl BNF, returns IR
sub perl_pipeline {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_parser();
    return parse_ir($parser, perl_bnf_text());
}

# Reorder grammar rules so the given start symbol is first.
# Returns the original grammar arrayref if no start option given.
my sub _reorder_grammar($grammar, %opts) {
    return $grammar unless defined $opts{start};

    my $start = $opts{start};
    my @reordered;
    my $found = false;
    for my $rule ($grammar->@*) {
        if (!$found && $rule->name() eq $start) {
            unshift @reordered, $rule;
            $found = true;
        } else {
            push @reordered, $rule;
        }
    }
    die "Start rule '$start' not found in grammar" unless $found;
    return \@reordered;
}

# Builds a 5-ary FilterComposite Earley parser with the given actions object.
# FilterComposite: [Boolean, Precedence, TypeInference, Structural, SemanticAction]
my sub _build_perl_parser_with_actions($grammar, $actions, %opts) {
    my $ordered = _reorder_grammar($grammar, %opts);
    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar($ordered);

    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    my $comp_sr = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $type_sr, $struct_sr, $sem_sr],
    );

    return Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $comp_sr,
    );
}

# Builds a Boolean recognizer from the generated Perl grammar IR.
# Accepts optional start => 'RuleName' to select the start symbol.
# Without start, uses the first rule in the grammar array (Earley default).
sub build_perl_recognizer {
    my ($grammar, %opts) = @_;
    my $ordered = _reorder_grammar($grammar, %opts);
    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar($ordered);
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    return Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $bool_sr,
    );
}

# Builds a FilterComposite(Boolean, Precedence, TypeInference, Structural, SemanticAction(ConciseTree::Actions))
# parser from the generated Perl grammar IR. Accepts optional start => 'RuleName'.
# Result tuple indices: [0]=Boolean, [1]=Precedence, [2]=TypeInference, [3]=Structural, [4]=SemanticAction
sub build_perl_concise_parser {
    my ($grammar, %opts) = @_;
    return _build_perl_parser_with_actions(
        $grammar, Chalk::Bootstrap::ConciseTree::Actions->new(), %opts,
    );
}

# Builds a FilterComposite(Boolean, Precedence, TypeInference, Structural, SemanticAction(Perl::Actions))
# parser from the generated Perl grammar IR. Accepts optional start => 'RuleName'.
# Result tuple indices: [0]=Boolean, [1]=Precedence, [2]=TypeInference, [3]=Structural, [4]=SemanticAction
sub build_perl_ir_parser {
    my ($grammar, %opts) = @_;
    return _build_perl_parser_with_actions(
        $grammar, Chalk::Bootstrap::Perl::Actions->new(), %opts,
    );
}

# Compare two grammars structurally (rule names, alternatives, symbols)
# Returns true if they match, false otherwise
sub grammars_match {
    my ($gen_grammar, $ref_grammar) = @_;
    return false unless scalar($gen_grammar->@*) == scalar($ref_grammar->@*);

    for my $i (0 .. $#{$ref_grammar}) {
        my $gen = $gen_grammar->[$i];
        my $ref = $ref_grammar->[$i];
        return false if $gen->name() ne $ref->name();
        return false if $gen->alternative_count() != $ref->alternative_count();

        for my $j (0 .. $#{$ref->expressions()}) {
            my $gen_alt = $gen->expressions()->[$j];
            my $ref_alt = $ref->expressions()->[$j];
            return false if scalar($gen_alt->@*) != scalar($ref_alt->@*);

            for my $k (0 .. $#{$ref_alt}) {
                my $gs = $gen_alt->[$k];
                my $rs = $ref_alt->[$k];
                return false if $gs->type() ne $rs->type()
                    || $gs->value() ne $rs->value()
                    || ($gs->quantifier() // '') ne ($rs->quantifier() // '');
            }
        }
    }
    return true;
}

1;
