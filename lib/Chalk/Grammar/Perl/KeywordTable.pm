# ABOUTME: Perl keyword lookup table for the TypeInference semiring.
# ABOUTME: Contains words with dedicated terminals in the grammar (either \b keywords or regex-prefix tokens).
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Grammar::Perl::KeywordTable {
    # Keywords: words that have dedicated terminals in the grammar.
    # Includes /keyword\b/ terminals and regex-prefix tokens (m, s, qr).
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
        map grep
        qw m s qr
    );

    # Returns true if the word is a grammar keyword, false otherwise.
    sub is_keyword($word) {
        return $KEYWORDS{$word} // false;
    }
}
