package Chalk::Grammar::BNF;
# ABOUTME: Hand-coded BNF grammar for parsing BNF files without regex dependency
# ABOUTME: Defines BNF syntax in Perl for bootstrapping the BNF parser

use 5.42.0;
use experimental 'class';
use Chalk::Grammar;
use Chalk::Grammar::BNF::Rule::Grammar;
use Chalk::Grammar::BNF::Rule::LineList;
use Chalk::Grammar::BNF::Rule::Line;
use Chalk::Grammar::BNF::Rule::GrammarRule;
use Chalk::Grammar::BNF::Rule::RHS;
use Chalk::Grammar::BNF::Rule::RHSElement;
use Chalk::Grammar::BNF::Rule::Terminal;
use Chalk::Grammar::BNF::Rule::BarewordTerminal;
use Chalk::Grammar::BNF::Rule::Nonterminal;
use Chalk::Grammar::BNF::Rule::PatternDef;
use Chalk::Grammar::BNF::Rule::PatternRef;
use Chalk::Grammar::BNF::Rule::Comment;
use Chalk::Grammar::BNF::Rule::BlankLine;

# Export singleton grammar instance
our $grammar;

sub grammar {
    # Works as both sub and method
    shift if @_ && (!ref($_[0]) && $_[0] eq __PACKAGE__);
    return $grammar;
}

# Helper to create rules with custom classes
sub _new_bnf_rule {
    my ($lhs, $rhs, $probability) = @_;
    $probability ||= 1.0;

    # Map LHS nonterminal to appropriate rule class
    my $rule_class = "Chalk::Grammar::BNF::Rule::$lhs";
    my $rule_file = $rule_class;
    $rule_file =~ s|::|/|g;
    $rule_file .= ".pm";

    # Check if the specialized class exists
    if (eval { require $rule_file; 1 }) {
        return $rule_class->new(
            lhs => $lhs,
            rhs => $rhs,
            probability => $probability
        );
    }

    # Fall back to default GrammarRule
    return Chalk::GrammarRule->new(
        lhs => $lhs,
        rhs => $rhs,
        probability => $probability
    );
}

# Build the BNF grammar with semantic action support
sub _build_bnf_grammar {
    my @rules_array = @_;
    my %rules = ();

    for my $r (@rules_array) {
        my ($lhs, $rhs, $prob) = @$r;
        push(@{$rules{$lhs} //= []}, _new_bnf_rule($lhs, $rhs, $prob));
    }

    return Chalk::Grammar->new(
        rules => \%rules,
        start_symbol => $rules_array[0]->[0]
    );
}

# Hand-coded BNF grammar rules
# This grammar is used to parse BNF files like grammar/perl.bnf
$grammar = _build_bnf_grammar(
        # Top level: a BNF file is a list of lines
        ['Grammar', ['LineList']],

        # Lines can be empty, a single line, or contain more lines
        ['LineList', []],  # Empty (base case)
        ['LineList', ['Line']],  # Single line
        ['LineList', ['Line', 'LineList']],  # Multiple lines

        # A line can be a pattern definition, grammar rule, comment, or blank
        # Note: lines in BNF files end with newlines (handled by Line rules)
        ['Line', ['PatternDef', "\n"]],
        ['Line', ['GrammarRule', "\n"]],
        ['Line', ['Comment', "\n"]],
        ['Line', ['BlankLine']],

        # Pattern definitions: %NAME% = /regex/flags or //regex//flags
        # Example: %PATTERN_1% = /unless|if|while/u
        # Example: %PATTERN_21% = //(?:[^/\\]|\\.)*+//u
        # Example: %PATTERN_38% = /\|\||///u  (captures rest of line, semantic action parses)
        ['PatternDef', [
            '%',
            qr/[a-zA-Z_][a-zA-Z0-9_]*/,  # Pattern name
            '%',
            qr/\s*/,                      # Optional whitespace
            '=',
            qr/\s*/,                      # Optional whitespace
            '/',
            qr/[^\n]+/,                   # Rest of line (semantic action will parse)
        ]],

        # Pattern definition with double-slash delimiter
        # Inside //, single / is allowed, but // is the terminator
        ['PatternDef', [
            '%',
            qr/[a-zA-Z_][a-zA-Z0-9_]*/,  # Pattern name
            '%',
            qr/\s*/,                      # Optional whitespace
            '=',
            qr/\s*/,                      # Optional whitespace
            '//',
            qr/(?:[^\/\\]++|\\.|\/(?!\/))*+/,  # Regex content (/ allowed, but not //)
            '//',
            qr/[a-z]*/                    # Optional flags
        ]],

        # Grammar rules: LHS -> RHS
        # Example: Block -> '{' WS_OPT StatementList WS_OPT '}'
        ['GrammarRule', [
            qr/[A-Z][a-zA-Z0-9_]*/,  # LHS (nonterminal, starts with capital)
            qr/\s*/,                  # Optional whitespace
            '->',
            qr/\s*/,                  # Optional whitespace
            'RHS'
        ]],

        # Right-hand side: sequence of RHS elements or empty
        ['RHS', []],  # Empty RHS (epsilon production)
        ['RHS', ['RHSElement']],
        ['RHS', ['RHSElement', qr/\s+/, 'RHS']],

        # RHS elements can be terminals, nonterminals, pattern references, or barewords
        ['RHSElement', ['Terminal']],
        ['RHSElement', ['Nonterminal']],
        ['RHSElement', ['PatternRef']],
        ['RHSElement', ['BarewordTerminal']],

        # Terminals: single-quoted strings
        # Example: 'foo', '{', '}'
        ['Terminal', ["'", qr/(?:[^'\\]|\\.)*/, "'"]],

        # Bareword terminals: lowercase identifiers (keywords like class, method, field)
        # Example: class, method, field
        ['BarewordTerminal', [qr/[a-z][a-z0-9_]*/]],

        # Nonterminals: identifiers starting with capital letter
        # Example: Block, StatementList, WS_OPT
        ['Nonterminal', [qr/[A-Z][a-zA-Z0-9_]*/]],

        # Pattern references: %NAME%
        # Example: %PATTERN_1%
        ['PatternRef', [
            '%',
            qr/[a-zA-Z_][a-zA-Z0-9_]*/,
            '%'
        ]],

        # Comments: # followed by anything until newline
        ['Comment', [qr/#[^\n]*/]],

        # Blank lines: just a newline
        ['BlankLine', [qr/\n/]],
);

1;
