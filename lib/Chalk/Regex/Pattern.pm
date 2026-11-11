# ABOUTME: Reads a constant regex into atoms (literal bytes, classes, groups,
# ABOUTME: quantifiers, code blocks) for a matcher to be built from; refuses the rest by name.
package Chalk::Regex::Pattern;
use 5.42.0;
use utf8;

# G6 FRONT HALF, out of Chalk::Target::LLVM::Context: compile() is pure
# (pattern + flags -> atoms), the reader of Context's emitter. A construct it
# does not read dies GAP -- never a silent wrong match. (The T2 graph builder
# reads patterns with Chalk::Regex::Parse, into a tree.)

# compile($pattern, $flags) -> \%compiled
#
# Parse a literal regex pattern into the compiled form the emitter consumes:
# a sequence of one-byte ATOMS plus anchor flags. Atom kinds:
#   { kind => 'lit',   byte => $ord }                  — exact byte
#   { kind => 'class', neg => 0|1, ranges => [[lo,hi],...] }
#                                                      — byte in (or not in)
#                                                        any of the ranges
#                                                        (singles are [b,b])
#   { kind => 'any' }                                  — . (any byte but \n)
# Shorthands \d \w \s (and \D \W \S) desugar to classes; a backslash escape
# of a metachar (\. \[ \$ ...) is a literal byte. T3 adds per-atom quantifiers.
# Byte escapes the G6 sub-compiler resolves (regex-language escapes).
my %REGEX_ESCAPE_BYTE = (
    t => 0x09, n => 0x0A, r => 0x0D, f => 0x0C, a => 0x07, e => 0x1B, '0' => 0x00,
);

# escape_byte(\@chars, $idx, $pattern) -> ($byte, $consumed)
#
# Resolve a backslash escape; $idx is the char AFTER the backslash. Returns
# the byte value and how many pattern chars were consumed (1, or 3 for \xHH).
# Escaped punctuation is the literal byte; \t \n \r \f \a \e \0 map to their
# control bytes; \xHH parses two hex digits. Assertion and unknown
# ALPHANUMERIC escapes (\b \B \A \z \Z \G \p \N \c ...) DIE LOUDLY — perl
# reserves them, so matching the literal letter would be a silent miscompile.
sub escape_byte {
    my ($chars, $idx, $pattern) = @_;
    my $e = $chars->[$idx];
    if ($e !~ /[A-Za-z0-9]/) {
        return (ord($e), 1);                # \. \[ \$ \\ \/ ...
    }
    if (exists $REGEX_ESCAPE_BYTE{$e}) {
        return ($REGEX_ESCAPE_BYTE{$e}, 1); # \t \n \r \f \a \e \0
    }
    if ($e eq 'x') {
        my $hex = join '', grep { defined } @{$chars}[ $idx + 1, $idx + 2 ];
        die "malformed \\x escape in regex pattern '$pattern' "
          . "(need two hex digits)" unless $hex =~ /^[0-9A-Fa-f]{2}$/;
        return (hex($hex), 3);
    }
    die "GAP: regex escape \\$e in pattern '$pattern' not supported by the G6 "
      . "sub-compiler (assertions \\b \\B \\A \\z \\Z \\G and classes \\p \\N "
      . "are pending tranches — refusing to silently match a literal '$e')";
}

# without_inert_u($pattern, $flags) -> $flags, less a `u` (unicode_strings,
# as `use v5.12`+ sets) that changes nothing here: it decides only how \w
# \s \d (and their negations), POSIX classes and /i treat a byte past
# ASCII, and a pattern with none of them matches the same bytes either way.
sub without_inert_u {
    my ($pattern, $flags) = @_;
    $flags //= '';
    return $flags unless $flags =~ /u/;
    return $flags if $flags =~ /i/
        || ( $pattern // '' ) =~ /\\[wWsSdDbBhHvVRXpPN]|\[:/;
    return $flags =~ s/u//gr;
}

sub compile {
    my ($pattern, $flags) = @_;
    $flags = without_inert_u($pattern, $flags);

    # No flag is implemented yet; silently ignoring one (e.g. /i compiling a
    # case-sensitive matcher, /x treating whitespace as literal atoms) would
    # be a silent miscompile. One gate here covers m//, qr//, and s///.
    die "GAP: regex flags '$flags' not yet supported by the G6 sub-compiler"
        if length($flags // '');

    # T1 anchors: a leading ^ anchors the match at offset 0; a trailing $
    # anchors the match end at the subject length (or before a final newline,
    # perl semantics). They are not literal bytes. A trailing escaped \$ is a
    # literal dollar — the $ is an anchor only when preceded by an EVEN run of
    # backslashes (\\$ = escaped backslash THEN anchor; \$ = literal dollar).
    my $anchored_start = 0;
    my $anchored_end   = 0;
    if ($pattern =~ /^\^/) {
        $anchored_start = 1;
        $pattern =~ s/^\^//;
    }
    if ($pattern =~ /(\\*)\$$/ && length($1) % 2 == 0) {
        $anchored_end = 1;
        $pattern =~ s/\$$//;
    }

    # Shorthand class definitions (byte ranges).
    my %SHORTHAND = (
        d => [ [ord('0'), ord('9')] ],
        w => [ [ord('0'), ord('9')], [ord('A'), ord('Z')], [ord('a'), ord('z')],
               [ord('_'), ord('_')] ],
        s => [ [0x09, 0x0D], [ord(' '), ord(' ')] ],   # \t \n \v \f \r space
    );

    my @atoms;
    my @paren_stack;   # open-group cap indices (undef = non-capturing)
    my $ngroups = 0;   # capture group counter
    my $ncode = 0;     # `(?{ ... })` blocks, numbered in pattern order
    my @chars = split //, $pattern;
    my $i = 0;
    while ($i <= $#chars) {
        my $c = $chars[$i];

        if ($c eq '\\') {
            # Escape: shorthand class, byte escape, or literal punctuation.
            my $e = $chars[ $i + 1 ]
                // die "regex pattern '$pattern' ends with a bare backslash";
            if ($e =~ /^[dwsDWS]$/) {
                push @atoms, {
                    kind   => 'class',
                    neg    => ($e =~ /[DWS]/) ? 1 : 0,
                    ranges => $SHORTHAND{ lc $e },
                };
                $i += 2;
                next;
            }
            my ($byte, $used) = escape_byte(\@chars, $i + 1, $pattern);
            push @atoms, { kind => 'lit', byte => $byte };
            $i += 1 + $used;
            next;
        }

        if ($c eq '[') {
            # Character class: [^? ... ] with ranges and escapes.
            my $j   = $i + 1;
            my $neg = 0;
            if (($chars[$j] // '') eq '^') { $neg = 1; $j++ }
            my @ranges;
            my $first = 1;   # a ] as the FIRST member is a literal ]
            while ($j <= $#chars) {
                my $cc = $chars[$j];
                last if $cc eq ']' && !$first;
                $first = 0;
                # Shorthand expansion inside the class: [\d_] etc.
                if ($cc eq '\\') {
                    my $e = $chars[ $j + 1 ]
                        // die "regex class in '$pattern' ends with a bare backslash";
                    if ($e =~ /^[dwsDWS]$/) {
                        die "GAP: regex class shorthand \\$e inside [...] not yet supported "
                          . "in pattern '$pattern'" if $e =~ /[DWS]/;
                        push @ranges, $SHORTHAND{ lc $e }->@*;
                        $j += 2;
                        next;
                    }
                }
                # One endpoint: a plain char or a resolved escape byte.
                my ($lo, $lo_used);
                if ($cc eq '\\') {
                    ($lo, $lo_used) = escape_byte(\@chars, $j + 1, $pattern);
                    $lo_used += 1;   # the backslash itself
                }
                else {
                    ($lo, $lo_used) = (ord($cc), 1);
                }
                my $k = $j + $lo_used;
                # Range lo-hi (a dash that is not the last member)?
                if (($chars[$k] // '') eq '-' && ($chars[ $k + 1 ] // ']') ne ']') {
                    my ($hi, $hi_used);
                    if ($chars[ $k + 1 ] eq '\\') {
                        ($hi, $hi_used) = escape_byte(\@chars, $k + 2, $pattern);
                        $hi_used += 1;
                    }
                    else {
                        ($hi, $hi_used) = (ord($chars[ $k + 1 ]), 1);
                    }
                    # Perl rejects a descending range at compile time; matching
                    # nothing silently would be a miscompile.
                    die "invalid [] range (lo > hi) in regex pattern '$pattern'"
                        if $lo > $hi;
                    push @ranges, [ $lo, $hi ];
                    $j = $k + 1 + $hi_used;
                    next;
                }
                push @ranges, [ $lo, $lo ];
                $j = $k;
            }
            die "unterminated character class in regex pattern '$pattern'"
                unless ($chars[$j] // '') eq ']';
            push @atoms, { kind => 'class', neg => $neg, ranges => \@ranges };
            $i = $j + 1;
            next;
        }

        if ($c eq '.') {
            push @atoms, { kind => 'any' };
            $i++;
            next;
        }

        # Capture groups (T4): zero-width gopen/gclose markers around the
        # enclosed atoms. (?:...) is non-capturing (markers with cap undef —
        # transparent without alternation, but tracked so ')' pairs up).
        # Quantified groups ((ab)+) are a pending tranche.
        if ($c eq '(') {
            my $cap;
            if (($chars[$i+1] // '') eq '?' && ($chars[$i+2] // '') eq ':') {
                $cap = undef;     # non-capturing
                $i += 3;
            }
            # A CODE BLOCK runs where matching passes it: a zero-width atom,
            # numbered -- its body is the match's code_bodies entry.
            elsif (($chars[$i+1] // '') eq '?' && ($chars[$i+2] // '') eq '{') {
                push @atoms, { kind => 'code', n => $ncode++ };
                $i = code_block_end(\@chars, $i + 3);
                next;
            }
            elsif (($chars[$i+1] // '') eq '?') {
                die "GAP: regex (?...) construct (lookaround/modifier/code) in "
                  . "pattern '$pattern' not supported";
            }
            else {
                $cap = ++$ngroups;
                $i++;
            }
            push @atoms, { kind => 'gopen', cap => $cap };
            push @paren_stack, $cap;
            next;
        }
        if ($c eq ')') {
            die "unbalanced ')' in regex pattern '$pattern'"
                unless @paren_stack;
            my $cap = pop @paren_stack;
            push @atoms, { kind => 'gclose', cap => $cap };
            $i++;
            next;
        }

        # Quantifiers (T3): attach {min,max} to the PRECEDING atom. max undef
        # = unbounded. A quantifier with no preceding atom is malformed.
        # A `{` THAT OPENS NO COUNT ({n} {n,} {n,m} {,m}) is a literal brace,
        # as perl reads it: `m{a{b}c}` was refused as malformed (pvm 379).
        # Blanks may stand by the braces and the comma (perl 5.34).
        my $count_re = qr/^\{[ \t]*(?:(\d+)[ \t]*(,[ \t]*(\d*))?|,[ \t]*(\d+))[ \t]*\}/;
        if ($c =~ /[*+?]/ || ( $c eq '{' && join('', @chars[ $i .. $#chars ]) =~ $count_re )) {
            die "regex quantifier '$c' with no preceding atom in pattern '$pattern'"
                unless @atoms;
            my $atom = $atoms[-1];
            die "GAP: quantified group (...)$c in pattern '$pattern' not yet "
              . "supported by the G6 sub-compiler (tranche pending)"
                if $atom->{kind} eq 'gclose';
            die "GAP: regex quantifier '$c' directly after '(' in pattern '$pattern'"
                if $atom->{kind} eq 'gopen';
            die "GAP: a quantified regex code block in pattern '$pattern'\n"
                if $atom->{kind} eq 'code';
            die "GAP: double quantifier on one atom in pattern '$pattern' "
              . "(non-greedy *? +? ?? not yet supported)"
                if exists $atom->{min};
            if ($c eq '*') { $atom->{min} = 0; $atom->{max} = undef; $i++; next }
            if ($c eq '+') { $atom->{min} = 1; $atom->{max} = undef; $i++; next }
            if ($c eq '?') { $atom->{min} = 0; $atom->{max} = 1;     $i++; next }
            # {n} {n,} {n,m}
            my $rest = join '', @chars[ $i .. $#chars ];
            if ($rest =~ $count_re) {
                # {,m} is {0,m}
                my ($n, $has_comma, $m) = defined $4 ? (0, 1, $4) : ($1, defined $2, $3);
                $atom->{min} = 0 + $n;
                $atom->{max} = $has_comma ? (length($m // '') ? 0 + $m : undef) : 0 + $n;
                die "regex {n,m} with m < n in pattern '$pattern'"
                    if defined $atom->{max} && $atom->{max} < $atom->{min};
                $i += length($&);
                next;
            }
            die "malformed regex counted quantifier near '"
              . substr($rest, 0, 8) . "' in pattern '$pattern'";
        }

        # Unsupported metachars die loudly rather than silently matching as
        # literals (alternation arrives in T5). Mid-pattern ^/$ are perl
        # ASSERTIONS (usually unmatchable without /m) — matching them as
        # literal bytes would silently diverge.
        # (A lone `}` is a literal brace, as perl reads it.)
        if ($c =~ /[|^\$]/) {
            die "GAP: regex metachar '$c' in pattern '$pattern' not yet supported "
              . "by the G6 sub-compiler (tranche pending; mid-pattern ^/\$ are "
              . "assertions, not literals)";
        }

        push @atoms, { kind => 'lit', byte => ord($c) };
        $i++;
    }

    die "unbalanced '(' in regex pattern '$pattern'" if @paren_stack;

    return {
        atoms          => \@atoms,
        anchored_start => $anchored_start,
        anchored_end   => $anchored_end,
        ngroups        => $ngroups,
        ncode          => $ncode,
    };
}

# code_block_end(\@chars, $k) -> the index just past the `})` closing a
# `(?{` block whose code starts at $k. Braces nest; a quoted string's are
# text (`length("}}}")`), as perl's parser reads them.
sub code_block_end {
    my ($chars, $k) = @_;
    # A QUOTE-LIKE OP (q(...), qq{}, m//, s///, tr), A COMMENT OR A HEREDOC can
    # hold a `})` this scan would take for the end: refused, not misread.
    my $rest = join '', @$chars[ $k .. $#$chars ];
    die "GAP: a regex code block with a quote-like op, a comment or a heredoc is not lowered"
      . " -- where it ends is not found by braces and quotes\n"
        if $rest =~ /(?<![\w\$\@%&*>"'-])(?:q[qwr]?|m|s|tr|y)\s*[^\w\s=,;)]/ || $rest =~ /#|<</;
    my $depth = 1;
    while ($k < @$chars) {
        my $c = $chars->[$k];
        if ($c eq '"' || $c eq "'") {
            my $q = $c;
            for ($k++; $k < @$chars && $chars->[$k] ne $q; $k++) { $k++ if $chars->[$k] eq '\\' }
        }
        elsif ($c eq '{') { $depth++ }
        elsif ($c eq '}' && !--$depth) {
            die "GAP: a regex code block not closed by })\n" unless ( $chars->[ $k + 1 ] // '' ) eq ')';
            return $k + 2;
        }
        $k++;
    }
    die "GAP: a regex code block that is not closed\n";
}

1;
