# ABOUTME: Perl keyword lookup table for the TypeInference semiring.
# ABOUTME: Contains words with dedicated \b terminals in the grammar; builtins like return/die are NOT keywords.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Grammar::Perl::KeywordTable {
    # Keywords: words that have dedicated /keyword\b/ terminals in the grammar.
    # These are NOT builtins (return, die, push, etc.) which parse as
    # Identifier → CallExpression legitimately.
    my %KEYWORDS = map { $_ => true } qw(
        use class sub method ADJUST
        if unless elsif else
        while until for foreach
        my our state local field
        not and or xor
        eq ne lt gt le ge cmp isa x
        undef true false
    );

    # Returns true if the word is a grammar keyword, false otherwise.
    sub is_keyword($word) {
        return $KEYWORDS{$word} // false;
    }
}
