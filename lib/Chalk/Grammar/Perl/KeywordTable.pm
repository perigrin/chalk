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
    #   Control flow: return (dedicated grammar rule; must not parse as identifier)
    #   Note: 'die' is NOT listed here because its only parse path is through
    #   CallExpression(QualifiedIdentifier ...), which requires 'die' to scan
    #   as a QualifiedIdentifier. Adding 'die' here would block that path.
    my %KEYWORDS = map { $_ => true } qw(
        use no class sub method ADJUST package
        if unless elsif else
        while until for foreach
        try catch
        my our state local field
        BEGIN CHECK UNITCHECK INIT END
        not and or xor
        eq ne lt gt le ge cmp isa x
        undef true false
        qw q qq m s qr
        __SUB__
        return
    );

    # Returns true if the word is a grammar keyword, false otherwise.
    sub is_keyword($word) {
        return $KEYWORDS{$word} // false;
    }

    # Hard keywords: ALWAYS rejected as QualifiedIdentifier, regardless of
    # whether a keyword-consuming rule is predicted. These words are never
    # valid as function names in Perl and must not be admitted as identifiers
    # even when the Earley parser hasn't yet predicted their consuming rule
    # (e.g., due to nullable ElsifChain? completing IfStatement first).
    my %HARD_KEYWORDS = map { $_ => true } qw(
        else elsif
    );

    # Returns true if the word is a hard keyword that must always be rejected
    # as QualifiedIdentifier.
    sub is_hard_keyword($word) {
        return $HARD_KEYWORDS{$word} // false;
    }

    # Maps keywords to the grammar rule names that consume them.
    # Used by TypeInference.should_scan to check if a keyword-consuming
    # rule is predicted before rejecting the keyword as QualifiedIdentifier.
    # Returns arrayref of rule names or undef if keyword has no dedicated rules.
    my %KEYWORD_RULES = (
        'class'     => [qw(ClassBlock)],
        'sub'       => [qw(SubroutineDefinition AnonymousSub)],
        'method'    => [qw(MethodDefinition)],
        'use'       => [qw(UseDeclaration)],
        'no'        => [qw(UseDeclaration)],
        'if'        => [qw(IfStatement)],
        'unless'    => [qw(IfStatement)],
        'elsif'     => [qw(ElsifChain)],
        'else'      => [qw(ElsifChain)],
        'while'     => [qw(WhileStatement)],
        'until'     => [qw(WhileStatement)],
        'for'       => [qw(ForStatement ForeachStatement)],
        'foreach'   => [qw(ForeachStatement)],
        'my'        => [qw(VariableDeclaration ForeachStatement)],
        'our'       => [qw(VariableDeclaration)],
        'state'     => [qw(VariableDeclaration)],
        'local'     => [qw(VariableDeclaration)],
        'field'     => [qw(VariableDeclaration)],
        'ADJUST'    => [qw(AdjustBlock)],
        'BEGIN'     => [qw(PhaserBlock)],
        'END'       => [qw(PhaserBlock)],
        'INIT'      => [qw(PhaserBlock)],
        'CHECK'     => [qw(PhaserBlock)],
        'UNITCHECK' => [qw(PhaserBlock)],
        'try'       => [qw(TryCatchStatement)],
        'catch'     => [qw(TryCatchStatement)],
        'not'       => [qw(UnaryExpression)],
        'undef'     => [qw(Literal)],
        'true'      => [qw(Literal)],
        'false'     => [qw(Literal)],
        'qw'        => [qw(QwLiteral)],
        '__SUB__'   => [qw(Atom)],
        # Control-flow keyword with a dedicated grammar rule.
        # Without this entry, CallExpression(QualifiedIdentifier WS ExpressionList)
        # also matches 'return EXPR', producing duplicate Return CFG nodes
        # alongside ReturnStatement.
        # 'die' is intentionally NOT listed here: its only parse path is through
        # CallExpression, which requires 'die' to scan as QualifiedIdentifier.
        'return'    => [qw(ReturnStatement)],
        # Quoting/regex prefix keywords: these are consumed by terminal regex
        # patterns inside StringLiteral/RegexLiteral, not by named grammar rules.
        # Mapping them here lets should_scan reject them as QualifiedIdentifier
        # when the containing rule is predicted (which is the normal case).
        's'         => [qw(RegexLiteral)],
        'm'         => [qw(RegexLiteral)],
        'qr'        => [qw(RegexLiteral)],
        'q'         => [qw(StringLiteral)],
        'qq'        => [qw(StringLiteral)],
        # Operators (and, or, xor, eq, ne, etc.) appear inside BinaryOp patterns,
        # not as rule-starting keywords, so they don't need keyword_rules entries.
    );

    # Returns arrayref of grammar rule names that consume the given keyword,
    # or undef if the word is not a keyword or has no dedicated rules.
    sub keyword_rules($word) {
        return $KEYWORD_RULES{$word};
    }
}
