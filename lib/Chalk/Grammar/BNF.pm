package Chalk::Grammar::BNF;
# ABOUTME: Hand-coded BNF grammar for parsing BNF files without regex dependency
# ABOUTME: Defines BNF syntax in Perl for bootstrapping the BNF parser

use 5.42.0;
use experimental 'class';
use Chalk::Grammar;

# Export singleton grammar instance
our $grammar;

sub grammar {
    # Works as both sub and method
    shift if @_ && (!ref($_[0]) && $_[0] eq __PACKAGE__);
    return $grammar;
}

# Hand-coded BNF grammar rules
# This grammar is used to parse BNF files like grammar/perl.bnf
$grammar = Chalk::Grammar->build_grammar(
    rules => [
        # Top level: a BNF file is a list of lines
        ['Grammar' => ['LineList']],

        # Lines can be empty, a single line, or contain more lines
        ['LineList' => []],  # Empty (base case)
        ['LineList' => ['Line']],  # Single line
        ['LineList' => ['Line', 'LineList']],  # Multiple lines

        # A line can be a pattern definition, grammar rule, comment, or blank
        # Note: lines in BNF files end with newlines (handled by Line rules)
        ['Line' => ['PatternDef', "\n"]],
        ['Line' => ['GrammarRule', "\n"]],
        ['Line' => ['Comment', "\n"]],
        ['Line' => ['BlankLine']],

        # Pattern definitions: %NAME% = /regex/flags or //regex//flags
        # Example: %PATTERN_1% = /unless|if|while/u
        # Example: %PATTERN_21% = //(?:[^/\\]|\\.)*+//u
        ['PatternDef' => [
            '%',
            qr/[a-zA-Z_][a-zA-Z0-9_]*/,  # Pattern name
            '%',
            qr/\s*/,                      # Optional whitespace
            '=',
            qr/\s*/,                      # Optional whitespace
            '/',
            qr/(?:[^\/\\]|\\.)*/,         # Regex content (non-greedy, handle escapes)
            '/',
            qr/[a-z]*/                    # Optional flags
        ]],

        # Pattern definition with double-slash delimiter
        # Inside //, single / is allowed, but // is the terminator
        ['PatternDef' => [
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
        ['GrammarRule' => [
            qr/[A-Z][a-zA-Z0-9_]*/,  # LHS (nonterminal, starts with capital)
            qr/\s*/,                  # Optional whitespace
            '->',
            qr/\s*/,                  # Optional whitespace
            'RHS'
        ]],

        # Right-hand side: sequence of RHS elements or empty
        ['RHS' => []],  # Empty RHS (epsilon production)
        ['RHS' => ['RHSElement']],
        ['RHS' => ['RHSElement', qr/\s+/, 'RHS']],

        # RHS elements can be terminals, nonterminals, or pattern references
        ['RHSElement' => ['Terminal']],
        ['RHSElement' => ['Nonterminal']],
        ['RHSElement' => ['PatternRef']],

        # Terminals: single-quoted strings
        # Example: 'foo', '{', '}'
        ['Terminal' => ["'", qr/(?:[^'\\]|\\.)*/, "'"]],

        # Nonterminals: identifiers starting with capital letter
        # Example: Block, StatementList, WS_OPT
        ['Nonterminal' => [qr/[A-Z][a-zA-Z0-9_]*/]],

        # Pattern references: %NAME%
        # Example: %PATTERN_1%
        ['PatternRef' => [
            '%',
            qr/[a-zA-Z_][a-zA-Z0-9_]*/,
            '%'
        ]],

        # Comments: # followed by anything until newline
        ['Comment' => [qr/#[^\n]*/]],

        # Blank lines: just a newline
        ['BlankLine' => [qr/\n/]],
    ]
);

1;
