# ABOUTME: Chalk grammar for parsing BNF files using the Chalk parser itself
# ABOUTME: Dog-fooding approach - BNF grammar defined using Chalk::Grammar
package Chalk::Grammar::BNF;
use 5.42.0;
use utf8;
use Exporter 'import';
use Chalk::Grammar;

our @EXPORT_OK = qw($chalk_bnf_grammar);

# Hand-coded BNF meta-grammar
# This breaks the bootstrap cycle: meta-grammar is hand-coded in Perl,
# then used to parse BNF files which can define other grammars
our $chalk_bnf_grammar = Chalk::Grammar->build_grammar(
    auto_insert => ['WS_OPT'],
    rules => [
        # Top level: file contains lines
        ['BNFFile' => ['LineList']],

        ['LineList' => []],  # Empty file
        ['LineList' => ['Line', 'LineList']],

        ['Line' => ['PatternDef']],
        ['Line' => ['GrammarRule']],
        ['Line' => ['Comment']],

        # Pattern definition: %NAME% = /pattern/flags
        ['PatternDef' => ['PatternName', '=', 'RegexLiteral']],
        ['PatternName' => [qr/%(\w+)%/]],
        ['RegexLiteral' => [qr{/(.+)/([\w]*)}]],  # Greedy: matches to last /

        # Grammar rule: LHS -> RHS
        ['GrammarRule' => ['Identifier', '->', 'RHS']],
        ['RHS' => ['TokenList']],
        ['RHS' => []],  # Empty RHS (epsilon rule)

        ['TokenList' => ['Token']],
        ['TokenList' => ['Token', 'TokenList']],

        ['Token' => ['Terminal']],
        ['Token' => ['PatternRef']],
        ['Token' => ['Identifier']],
        ['Token' => ['SymbolToken']],

        ['Terminal' => [qr/'([^']*)'/]],
        ['PatternRef' => [qr/%(\w+)%/]],
        ['Identifier' => [qr/([a-zA-Z_][\w:]*)/]],
        ['SymbolToken' => [qr/([^\s'\/%]+)/]],  # ::, !, etc - non-letter tokens

        ['Comment' => [qr/#[^\n]*/]],

        # Whitespace handling
        ['WS_OPT' => []],
        ['WS_OPT' => ['WS']],
        ['WS_OPT' => ['WS', 'WS_OPT']],
        ['WS' => [qr/[ \t\n]+/]],
    ]
);

1;
