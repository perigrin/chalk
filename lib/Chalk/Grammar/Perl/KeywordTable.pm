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
}
