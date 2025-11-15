# ABOUTME: Hand-coded BNF grammar for parsing BNF files without regex dependency
# ABOUTME: Defines BNF syntax in Perl for bootstrapping the BNF parser
use 5.42.0;
use experimental qw(class);

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

class Chalk::Grammar::BNF {

    # Singleton grammar instance
    # Hand-coded BNF grammar rules
    # This grammar is used to parse BNF files like grammar/chalk.bnf
    field $grammar :reader = Chalk::Grammar->new(
        rules => {
            Grammar => [

                # Top level: a BNF file is a list of lines
                Chalk::Grammar::BNF::Rule::Grammar->new(
                    lhs => 'Grammar',
                    rhs => ['LineList']
                ),
            ],

            LineList => [

                # Lines can be empty, a single line, or contain more lines
                Chalk::Grammar::BNF::Rule::LineList->new(
                    lhs => 'LineList',
                    rhs => []
                ),    # Empty (base case)
                Chalk::Grammar::BNF::Rule::LineList->new(
                    lhs => 'LineList',
                    rhs => ['Line']
                ),    # Single line
                Chalk::Grammar::BNF::Rule::LineList->new(
                    lhs => 'LineList',
                    rhs => [ 'Line', 'LineList' ]
                ),    # Multiple lines
            ],

            Line => [

           # A line can be a pattern definition, grammar rule, comment, or blank
           # Note: lines in BNF files end with newlines (handled by Line rules)
                Chalk::Grammar::BNF::Rule::Line->new(
                    lhs => 'Line',
                    rhs => [ 'PatternDef', "\n" ]
                ),
                Chalk::Grammar::BNF::Rule::Line->new(
                    lhs => 'Line',
                    rhs => [ 'GrammarRule', "\n" ]
                ),
                Chalk::Grammar::BNF::Rule::Line->new(
                    lhs => 'Line',
                    rhs => [ 'Comment', "\n" ]
                ),
                Chalk::Grammar::BNF::Rule::Line->new(
                    lhs => 'Line',
                    rhs => ['BlankLine']
                ),
            ],

            PatternDef => [

# Pattern definitions: %NAME% = /regex/flags
# Example: %PATTERN_1% = /unless|if|while/u
# Example: %PATTERN_38% = /\|\||///u  (captures rest of line, semantic action parses)
                Chalk::Grammar::BNF::Rule::PatternDef->new(
                    lhs => 'PatternDef',
                    rhs => [
                        '%',
                        qr/([a-zA-Z_][a-zA-Z0-9_]*)/,    # Pattern name
                        '%',
                        qr/(\s*)/,                       # Optional whitespace
                        '=',
                        qr/(\s*)/,                       # Optional whitespace
                        '/',
                        qr/([^\n]+)/,  # Rest of line (semantic action will parse)
                    ]
                ),
            ],

            GrammarRule => [

                # Grammar rules: LHS -> RHS (with optional inline comment)
                # Example: Block -> '{' WS_OPT StatementList WS_OPT '}'
                # Example with comment: Foo -> 'bar'  # inline comment
                Chalk::Grammar::BNF::Rule::GrammarRule->new(
                    lhs => 'GrammarRule',
                    rhs => [
                        qr/([A-Z][a-zA-Z0-9_]*)/
                        ,           # LHS (nonterminal, starts with capital)
                        qr/(\s*)/,    # Optional whitespace
                        '->',
                        qr/(\s*)/,    # Optional whitespace
                        'RHS',
                        qr/(\s*#[^\n]*)/
                        ,           # Inline comment (with leading whitespace)
                    ]
                ),
                Chalk::Grammar::BNF::Rule::GrammarRule->new(
                    lhs => 'GrammarRule',
                    rhs => [
                        qr/([A-Z][a-zA-Z0-9_]*)/
                        ,           # LHS (nonterminal, starts with capital)
                        qr/(\s*)/,    # Optional whitespace
                        '->',
                        qr/(\s*)/,    # Optional whitespace
                        'RHS'
                    ]
                ),
            ],

            RHS => [

                # Right-hand side: sequence of RHS elements or empty
                Chalk::Grammar::BNF::Rule::RHS->new(
                    lhs => 'RHS',
                    rhs => []
                ),    # Empty RHS (epsilon production)
                Chalk::Grammar::BNF::Rule::RHS->new(
                    lhs => 'RHS',
                    rhs => ['RHSElement']
                ),
                Chalk::Grammar::BNF::Rule::RHS->new(
                    lhs => 'RHS',
                    rhs => [ 'RHSElement', qr/(\s+)/, 'RHS' ]
                ),
            ],

            RHSElement => [

 # RHS elements can be terminals, nonterminals, pattern references, or barewords
                Chalk::Grammar::BNF::Rule::RHSElement->new(
                    lhs => 'RHSElement',
                    rhs => ['Terminal']
                ),
                Chalk::Grammar::BNF::Rule::RHSElement->new(
                    lhs => 'RHSElement',
                    rhs => ['Nonterminal']
                ),
                Chalk::Grammar::BNF::Rule::RHSElement->new(
                    lhs => 'RHSElement',
                    rhs => ['PatternRef']
                ),
                Chalk::Grammar::BNF::Rule::RHSElement->new(
                    lhs => 'RHSElement',
                    rhs => ['BarewordTerminal']
                ),
            ],

            Terminal => [

                # Terminals: single-quoted strings
                # Example: 'foo', '{', '}'
                Chalk::Grammar::BNF::Rule::Terminal->new(
                    lhs => 'Terminal',
                    rhs => [ "'", qr/((?:[^'\\]|\\.)*)/, "'" ]
                ),
            ],

            BarewordTerminal => [

# Bareword terminals: lowercase identifiers (keywords like class, method, field)
# Example: class, method, field
                Chalk::Grammar::BNF::Rule::BarewordTerminal->new(
                    lhs => 'BarewordTerminal',
                    rhs => [qr/([a-z][a-z0-9_]*)/]
                ),

          # Symbol bareword terminals: operators and symbols (like ::, ->, etc.)
          # Example: ::, ->, ...
          # Note: Excludes # to prevent matching comments as barewords
                Chalk::Grammar::BNF::Rule::BarewordTerminal->new(
                    lhs => 'BarewordTerminal',
                    rhs => [qr/([^A-Z\s'%#][^A-Z\s'%#\->]*)/]
                ),
            ],

            Nonterminal => [

                # Nonterminals: identifiers starting with capital letter
                # Example: Block, StatementList, WS_OPT
                Chalk::Grammar::BNF::Rule::Nonterminal->new(
                    lhs => 'Nonterminal',
                    rhs => [qr/([A-Z][a-zA-Z0-9_]*)/]
                ),
            ],

            PatternRef => [

                # Pattern references: %NAME%
                # Example: %PATTERN_1%
                Chalk::Grammar::BNF::Rule::PatternRef->new(
                    lhs => 'PatternRef',
                    rhs => [ '%', qr/([a-zA-Z_][a-zA-Z0-9_]*)/, '%' ]
                ),
            ],

            Comment => [

                # Comments: # followed by anything until newline
                Chalk::Grammar::BNF::Rule::Comment->new(
                    lhs => 'Comment',
                    rhs => [qr/(#[^\n]*)/]
                ),
            ],

            BlankLine => [

                # Blank lines: just a newline
                Chalk::Grammar::BNF::Rule::BlankLine->new(
                    lhs => 'BlankLine',
                    rhs => [qr/(\n)/]
                ),
            ],
        },
        start_symbol => 'Grammar'
    );
}

1;
