# ABOUTME: Provides regex terminal matching anchored at \G position for scanless parsing.
# ABOUTME: Match method returns end position on success or undef on failure.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Terminal {

    # Each pattern anchored at \G, compiled once. Interpolating the pattern
    # into the match instead recompiles it whenever the pattern differs
    # from the one matched just before, which in a parser is nearly always.
    my %ANCHORED;

    # Class method for terminal matching.
    # Takes the input by value, which copies it: a parser that matches at
    # every position of one input calls match_at instead.
    sub match($input, $position, $pattern) {
        return match_at(\$input, $position, $pattern);
    }

    # Match $pattern at character $position of the string $input_ref
    # refers to. Returns the end position, or undef if the pattern does
    # not match there.
    #
    # The string is matched in place and the end is read back from pos(),
    # so a call costs the same wherever $position is. Perl keeps its
    # character-to-byte position cache on the string itself: a copy of a
    # UTF-8 string starts without one, and reading the end from a capture
    # ($1, @+) converts from the start of the string again. Either makes
    # every match linear in $position.
    #
    # Assigning pos() first also clears Perl's record of a previous
    # zero-width match there, so the same zero-width match succeeds each
    # time it is asked for.
    sub match_at($input_ref, $position, $pattern) {
        my $anchored = $ANCHORED{$pattern} //= qr/\G(?:$pattern)/;
        pos($input_ref->$*) = $position;
        if ($input_ref->$* =~ /$anchored/gc) {
            return pos($input_ref->$*);
        }
        return undef;
    }
}
