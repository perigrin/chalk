# ABOUTME: Provides regex terminal matching anchored at \G position for scanless parsing.
# ABOUTME: Match method returns end position on success or undef on failure.
use 5.42.0;
use utf8;

package Chalk::Bootstrap::Terminal {

    sub match($input, $position, $pattern) {
        # Set \G to the specified position
        pos($input) = $position;

        # Try to match at \G, capturing the match
        if ($input =~ /\G($pattern)/) {
            # Calculate end position from start + match length
            my $matched = $1;
            return $position + length($matched);
        }

        # No match
        return undef;
    }
}
