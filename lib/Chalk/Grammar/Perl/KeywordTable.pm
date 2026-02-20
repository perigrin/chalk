# ABOUTME: Perl keyword lookup table for the TypeInference semiring.
# ABOUTME: Contains words with dedicated grammar terminals that must not parse as QualifiedIdentifier.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Grammar::Perl::KeywordTable {
    # Keywords: words that have dedicated terminals in the grammar.
    # TypeInference kills QualifiedIdentifier paths for these to prevent
    # ambiguity between the identifier path and the dedicated terminal.
    #
    # Categories:
    #   Declarators:  use class sub method ADJUST package
    #   Conjunctions: if elsif else unless while until for foreach
    #   Variables:    my our state local field
    #   Phase blocks: BEGIN CHECK UNITCHECK INIT END
    #   Operators:    not and or xor eq ne lt gt le ge cmp isa x
    #   Literals:     undef true false
    #   Quoting:      qw q qq m s qr (prefix tokens for quoting/regex)
    #   Special:      __SUB__
    my %KEYWORDS = map { $_ => true } qw(
        use class sub method ADJUST package
        if unless elsif else
        while until for foreach
        my our state local field
        BEGIN CHECK UNITCHECK INIT END
        not and or xor
        eq ne lt gt le ge cmp isa x
        undef true false
        qw q qq m s qr
        __SUB__
    );

    # Returns true if the word is a grammar keyword, false otherwise.
    sub is_keyword($word) {
        return $KEYWORDS{$word} // false;
    }

    # Maps keywords to the grammar rule names that consume them.
    # Used by TypeInference.should_scan to check if a keyword-consuming
    # rule is predicted before rejecting the keyword as QualifiedIdentifier.
    # Returns arrayref of rule names or undef if keyword has no dedicated rules.
    my %KEYWORD_RULES = (
        'class'     => [qw(ClassDeclaration ClassBlock)],
        'sub'       => [qw(SubroutineDefinition SubroutineDeclaration AnonymousSub)],
        'method'    => [qw(MethodDefinition MethodDeclaration AnonymousSub)],
        'use'       => [qw(UseDeclaration)],
        'no'        => [qw(UseDeclaration)],
        'package'   => [qw(PackageDeclaration PackageBlock)],
        'if'        => [qw(ConditionalStatement)],
        'unless'    => [qw(ConditionalStatement)],
        'elsif'     => [qw(ElseChain)],
        'else'      => [qw(ElseChain)],
        'while'     => [qw(WhileLoop)],
        'until'     => [qw(WhileLoop)],
        'for'       => [qw(CStyleForLoop ForeachLoop)],
        'foreach'   => [qw(ForeachLoop)],
        'my'        => [qw(VariableDeclaration ForeachLoop)],
        'our'       => [qw(VariableDeclaration)],
        'state'     => [qw(VariableDeclaration)],
        'local'     => [qw(VariableDeclaration)],
        'field'     => [qw(FieldDeclaration)],
        'ADJUST'    => [qw(PhaserBlock)],
        'BEGIN'     => [qw(PhaserBlock)],
        'CHECK'     => [qw(PhaserBlock)],
        'UNITCHECK' => [qw(PhaserBlock)],
        'INIT'      => [qw(PhaserBlock)],
        'END'       => [qw(PhaserBlock)],
        'not'       => [qw(UnaryExpression)],
        'undef'     => [qw(Literal)],
        'true'      => [qw(Literal)],
        'false'     => [qw(Literal)],
        'qw'        => [qw(QuotedWords)],
        '__SUB__'   => [qw(Atom)],
        # Operators (and, or, xor, eq, ne, etc.) appear inside BinaryOp patterns,
        # not as rule-starting keywords, so they don't need keyword_rules entries.
        # Same for quoting operators q, qq, m, s, qr — they match dedicated terminals.
    );

    # Returns arrayref of grammar rule names that consume the given keyword,
    # or undef if the word is not a keyword or has no dedicated rules.
    sub keyword_rules($word) {
        return $KEYWORD_RULES{$word};
    }
}
