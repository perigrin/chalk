# ABOUTME: Mode-2 harvester extractor — parses a Test::More .t file and pulls each
# ABOUTME: is/cmp_ok/ok assertion into a corpus case, counting every un-harvestable one.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

# Extract Test::More assertions from a real perl5 t/ file into harvestable corpus
# cases. This is HARVESTER PIPELINE TOOLING, not compiler code: it produces case
# records; it lowers nothing.
#
# The parser is a PRAGMATIC line/regex scanner (the regex_scan.pl analyzer shape),
# NOT a full Perl parser. It reads the file line by line, finds assertion calls
# by leading keyword, and splits the argument list respecting quotes and nesting.
#
# KNOWN LIMITATIONS (each is a COUNTED, named skip — never a silent drop):
#   * multi-line assertions (the call spans >1 physical line) -> 'multiline-assertion'
#   * heredoc bodies are not tracked; a `<<` inside an assertion -> 'out-of-subset:heredoc'
#   * m{}-delimited / q{}-delimited quoting is not modelled; an unbalanced split
#     surfaces as 'unbalanced-args' rather than a wrong harvest.
#
# GAP-not-silent-skip invariant: extract_file returns
#   { cases, skips, histogram, total }  with  @cases + @skips == total,
# i.e. every assertion the scanner SEES is either harvested or counted-skipped.
class Chalk::CodeGen::Harness::Mode2Extractor {

    # Out-of-subset SUBJECT tokens (R5.3). Order matters only for which reason a
    # token reports first; the reason string NAMES the offending token so the
    # histogram doubles as a next-feature worklist. Each entry is
    # [ token-name => qr/matcher/ ].
    my @OUT_OF_SUBSET = (
        [ 'eval'     => qr/\beval\b/ ],
        [ 'open'     => qr/\bopen\b/ ],
        [ 'fork'     => qr/\bfork\b/ ],
        [ 'tie'      => qr/\btie\b/ ],
        [ 'format'   => qr/\bformat\b/ ],
        [ 'pack'     => qr/\b(?:un)?pack\b/ ],
        [ 'sprintf'  => qr/\bsprintf\b/ ],
        [ 'syscall'  => qr/\bsyscall\b/ ],
        [ 'heredoc'  => qr/<</ ],
        # $@ / $! / $? : cross-statement runtime state (an eval/system/open must
        # have run to make the subject meaningful) -> not self-contained.
        [ 'errvar'   => qr/\$[@!?]/ ],
        # typeglob / special-punctuation var: *FOO, ${^NAME}, $^X
        [ 'typeglob' => qr/(?:^|[^\w\$])\*\w|\$\{\^|\$\^/ ],
        # XS / package-qualified name  Foo::bar  (but not the trailing Moo:: bless)
        [ 'qualified-name' => qr/\w+::\w/ ],
        # regex binding / qr
        [ 'regex'    => qr/=~|!~|\bqr\b/ ],
    );

    # extract_file($path) -> { cases => [...], skips => [...],
    #                          histogram => { reason => count }, total => N }
    # Class method: the extractor is stateless (like HarvestPin), so callers need
    # no instance.
    sub extract_file ($class, $path) {
        open my $fh, '<:encoding(UTF-8)', $path
            or die "Mode2Extractor: cannot read $path: $!";
        my @lines = <$fh>;
        close $fh;

        # Gather block-local `my $x = <literal>;` preamble bindings the subject may
        # reference (R5.2), along with brace-depth and mutation info so preamble
        # resolution is scope- and mutation-aware (no stale/wrong harvests).
        my $ctx = $class->_gather_bindings(\@lines);

        my (@cases, @skips);
        my %hist;

        for my $i (0 .. $#lines) {
            my $lineno = $i + 1;
            my $text   = $lines[$i];

            my $call = $class->_match_assertion($text) or next;
            # $call = { kind => is|cmp_ok|ok, args_src => '...', complete => bool }

            my $rec = $class->_harvest($call, $path, $lineno, $ctx);

            if ($rec->{skip_reason}) {
                push @skips, {
                    file   => $path,
                    line   => $lineno,
                    reason => $rec->{skip_reason},
                    raw    => _trim_raw($text),
                };
                $hist{ $rec->{skip_reason} }++;
            }
            else {
                push @cases, $rec;
            }
        }

        return {
            cases     => \@cases,
            skips     => \@skips,
            histogram => \%hist,
            total     => scalar(@cases) + scalar(@skips),
        };
    }

    # --- assertion line detection -------------------------------------------
    # Returns { kind, args_src, complete } or undef. args_src is the raw text of
    # the argument list (whatever follows the keyword up to a matching close /
    # statement end on THIS line). `complete` is false when the call opened a
    # paren that did not close on this line (a multi-line assertion).
    sub _match_assertion ($class, $text) {
        # Leading whitespace then keyword. is/cmp_ok/ok may be paren-called
        #   is(...)   cmp_ok(...)   ok(...)
        # or paren-less (magic_phase.t):  ok EXPR, 'desc'
        return undef unless $text =~ /^\s*(is|cmp_ok|ok)\b(.*)$/s;
        my ($kind, $rest) = ($1, $2);

        # Drop a trailing comment that is clearly outside the args is hard to do
        # reliably; we keep $rest verbatim and let the splitter stop at the
        # statement's close. Determine paren vs paren-less form.
        if ($rest =~ /^\s*\(/) {
            # Paren form: capture balanced parens starting at the first '('.
            my ($inner, $ok) = _balanced_parens($rest);
            return { kind => $kind, args_src => $inner, complete => $ok };
        }
        else {
            # Paren-less form: args run to end of statement (a ';' at paren depth
            # 0) on this line. If none, treat as complete-to-EOL.
            my $args = $rest;
            $args =~ s/;\s*(?:#.*)?$//;   # strip trailing ; and comment
            return { kind => $kind, args_src => $args, complete => 1 };
        }
    }

    # --- harvest one assertion into a case (or a skip record) ---------------
    sub _harvest ($class, $call, $path, $lineno, $ctx) {
        my $kind = $call->{kind};

        return { skip_reason => 'multiline-assertion' } unless $call->{complete};

        my @args = _split_args($call->{args_src});
        return { skip_reason => 'unbalanced-args' } unless @args;

        my ($subject, $cmp, $expected);

        if ($kind eq 'is') {
            return { skip_reason => 'arity' } if @args < 2;
            ($subject, $expected) = ($args[0], $args[1]);
            $cmp = 'eq';
        }
        elsif ($kind eq 'cmp_ok') {
            return { skip_reason => 'arity' } if @args < 3;
            my $op = _as_literal($args[1]);
            return { skip_reason => 'non-literal-cmp' } unless defined $op;
            ($subject, $cmp, $expected) = ($args[0], $op, $args[2]);
        }
        else {   # ok(EXPR, DESC?)  -- expected is implicit truth
            $subject  = $args[0];
            $cmp      = 'ok';
            $expected = '1';   # truthiness oracle
        }

        # R5.3: out-of-subset SUBJECT tokens -> LOUD named skip.
        if (my $tok = _out_of_subset_token($subject)) {
            return { skip_reason => "out-of-subset:$tok" };
        }

        # R5.1: EXPECTED must be a compile-time literal (number/string/undef).
        # (For `ok`, expected is the literal 1 we synthesised — always literal.)
        if ($kind ne 'ok') {
            my $lit = _as_literal($expected);
            return { skip_reason => 'non-literal-expected' } unless defined $lit;
            $expected = $lit;
        }

        # R5.2: gather the block-local `my` preamble the subject references.
        my $pre = $class->_preamble_for($subject, $ctx, $lineno);
        return { skip_reason => $pre->{skip_reason} } if $pre->{skip_reason};

        return {
            subject  => $subject,
            expected => $expected,
            cmp      => $cmp,
            file     => $path,
            line     => $lineno,
            ( @{ $pre->{preamble} } ? (preamble => $pre->{preamble}) : () ),
        };
    }

    # --- R5.2 preamble resolution -------------------------------------------
    # Build the binding context: `my $x = <literal>;` scalar bindings (with the
    # brace depth at their declaration), the running brace depth per line, and the
    # set of lines that reassign/mutate each variable. This is what makes preamble
    # gathering SOUND rather than "nearest my wins" — a subject is only
    # self-contained if its binding is still in scope AND unmutated at the
    # assertion. Anything else is a COUNTED skip, never a stale/wrong harvest.
    #
    # Returns { bindings => [ {name, rhs, line, depth} ],
    #           depth    => [ depth-BEFORE-this-line, per 1-based line ],
    #           mutated  => { '$x' => [ line, ... ] } }.
    sub _gather_bindings ($class, $lines) {
        my (@b, @depth, %mutated);
        my $d = 0;
        for my $i (0 .. $#$lines) {
            my $t = $lines->[$i];
            $depth[ $i + 1 ] = $d;   # depth entering this line

            # my $x = <rhs>;   (single scalar only — list-assign is not simple)
            if ($t =~ /^\s*my\s+(\$\w+)\s*=\s*(.+?);\s*(?:#.*)?$/) {
                push @b, { name => $1, rhs => $2, line => $i + 1, depth => $d };
            }

            # Record any reassignment/mutation of a scalar on this line so a later
            # subject can reject a binding whose value changed after declaration:
            #   $x = ...    $x .= ...   $x += ...   $x++   ++$x   chop $x ...
            # We deliberately over-record (a `my $x =` also matches `$x =`); the
            # binding line itself is excluded when we query, so that is harmless.
            for my $v ($t =~ /(\$\w+)\s*(?:[-+.*\/%|&^]?=(?!=)|\+\+|--)/g) {
                push $mutated{$v}->@*, $i + 1;
            }
            for my $v ($t =~ /\+\+\s*(\$\w+)|--\s*(\$\w+)/g) {
                push $mutated{$v}->@*, $i + 1 if defined $v;
            }

            # Update running brace depth (net braces on this line). Pragmatic: we
            # do not exclude braces inside strings; miscounting only makes scope
            # checks MORE conservative (more skips), never a false harvest.
            my $opens = () = $t =~ /\{/g;
            my $closes = () = $t =~ /\}/g;
            $d += $opens - $closes;
        }
        return { bindings => \@b, depth => \@depth, mutated => \%mutated };
    }

    # For a subject, find the in-scope, unmutated simple bindings it names, and
    # build a self-contained preamble. A subject lexical is HARVESTABLE only if:
    #   (a) a `my $x = <literal>` binding is declared before the assertion,
    #   (b) that binding is still in scope — the brace depth never dropped below
    #       the binding's own depth between declaration and the assertion, and
    #   (c) $x is not reassigned/mutated between the binding and the assertion.
    # Any failure is a COUNTED skip ('unresolved-lexical'), never a wrong harvest.
    sub _preamble_for ($class, $subject, $ctx, $lineno) {
        my @vars = ($subject =~ /(\$\w+)/g);
        return { preamble => [] } unless @vars;

        my $subj_depth = $ctx->{depth}[$lineno] // 0;

        my %seen;
        my @pre;
        for my $v (@vars) {
            next if $seen{$v}++;

            # nearest earlier `my $v = literal` binding
            my ($bind) = grep { $_->{name} eq $v && $_->{line} < $lineno }
                reverse $ctx->{bindings}->@*;
            return { skip_reason => 'unresolved-lexical' } unless $bind;

            # (a) RHS must be a compile-time literal to be self-contained.
            return { skip_reason => 'unresolved-lexical' }
                unless defined _as_literal($bind->{rhs});

            # (b) scope: brace depth must never fall below the binding's depth
            # between declaration and the assertion (else they are different
            # blocks and the binding is not the one in scope).
            for my $ln ($bind->{line} + 1 .. $lineno) {
                if (($ctx->{depth}[$ln] // 0) < $bind->{depth}) {
                    return { skip_reason => 'unresolved-lexical' };
                }
            }

            # (c) no reassignment/mutation of $v strictly between binding and use.
            for my $mln (($ctx->{mutated}{$v} // [])->@*) {
                if ($mln > $bind->{line} && $mln <= $lineno) {
                    return { skip_reason => 'unresolved-lexical' };
                }
            }

            push @pre, "my $bind->{name} = $bind->{rhs};";
        }
        return { preamble => \@pre };
    }

    # === helpers (functions, not methods — no $self needed) =================

    # _out_of_subset_token($src) -> token-name or undef.
    sub _out_of_subset_token ($src) {
        for my $entry (@OUT_OF_SUBSET) {
            my ($name, $re) = @$entry;
            return $name if $src =~ $re;
        }
        return undef;
    }

    # _as_literal($src) -> canonical literal value, or undef if not a literal.
    # Recognises: number (int/float/hex-ish), single/double-quoted string, undef.
    # Returns the DECODED scalar for strings (quotes removed) so a case's expected
    # is the raw value; numbers are returned verbatim.
    sub _as_literal ($src) {
        my $s = $src;
        $s =~ s/^\s+//;
        $s =~ s/\s+$//;

        return undef unless length $s;

        # bareword undef
        return undef if $s eq '';
        if ($s eq 'undef') { return 'undef'; }

        # comparator operators passed to cmp_ok as quoted strings are handled by
        # the string branch below; a bareword op like ==, eq, < is ALSO a literal
        # comparator token.
        if ($s =~ m{^(?:==|!=|<=|>=|<|>|<=>|eq|ne|lt|gt|le|ge|cmp)$}) {
            return $s;
        }

        # number: optional sign, decimal / float / exponent. No expressions.
        if ($s =~ /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/) {
            return $s;
        }

        # single-quoted string: no interpolation, only \\ and \' escapes.
        if ($s =~ /^'((?:\\.|[^'\\])*)'$/) {
            my $inner = $1;
            $inner =~ s/\\(['\\])/$1/g;
            return $inner;
        }

        # double-quoted string WITHOUT interpolation metacharacters. A literal is
        # only literal if it has no $ / @ interpolation and no backslash escapes
        # we don't decode. Keep it strict: reject any $ or @ (interpolation).
        if ($s =~ /^"((?:\\.|[^"\\])*)"$/) {
            my $inner = $1;
            return undef if $inner =~ /(?<!\\)[\$\@]/;   # interpolation -> not literal
            # decode the common escapes we can represent as a literal value.
            $inner =~ s/\\([\\"])/$1/g;
            $inner =~ s/\\n/\n/g;
            $inner =~ s/\\t/\t/g;
            # any remaining backslash escape (\x, \0, \o...) is not a plain
            # literal we can canonicalise -> reject.
            return undef if $inner =~ /\\/;
            return $inner;
        }

        return undef;
    }

    # _balanced_parens($src) starting with optional ws + '(' -> ($inner, $complete)
    # $inner is the text BETWEEN the outermost parens; $complete is false if the
    # opening paren never closed on this line (multi-line call).
    sub _balanced_parens ($src) {
        $src =~ /^\s*\(/ or return ('', 0);
        my $start = $+[0];          # index just after the '('
        my $depth = 1;
        my $in_s  = 0;              # in single quote
        my $in_d  = 0;              # in double quote
        my $i     = $start;
        my $len   = length $src;
        while ($i < $len) {
            my $c = substr($src, $i, 1);
            if ($in_s) {
                $in_s = 0 if $c eq "'" && substr($src, $i - 1, 1) ne "\\";
            }
            elsif ($in_d) {
                $in_d = 0 if $c eq '"' && substr($src, $i - 1, 1) ne "\\";
            }
            elsif ($c eq "'") { $in_s = 1; }
            elsif ($c eq '"') { $in_d = 1; }
            elsif ($c eq '(') { $depth++; }
            elsif ($c eq ')') {
                $depth--;
                return (substr($src, $start, $i - $start), 1) if $depth == 0;
            }
            $i++;
        }
        return ('', 0);   # never closed -> incomplete (multi-line)
    }

    # _split_args($src) -> list of top-level comma-separated argument sources.
    # Respects nesting (), [], {} and single/double quotes. Returns () on an
    # unbalanced input so the caller can count it as 'unbalanced-args'.
    sub _split_args ($src) {
        my @args;
        my $cur   = '';
        my $depth = 0;
        my $in_s  = 0;
        my $in_d  = 0;
        my $len   = length $src;
        for (my $i = 0 ; $i < $len ; $i++) {
            my $c    = substr($src, $i, 1);
            my $prev = $i > 0 ? substr($src, $i - 1, 1) : '';
            if ($in_s) {
                $in_s = 0 if $c eq "'" && $prev ne "\\";
                $cur .= $c;
            }
            elsif ($in_d) {
                $in_d = 0 if $c eq '"' && $prev ne "\\";
                $cur .= $c;
            }
            elsif ($c eq "'") { $in_s = 1; $cur .= $c; }
            elsif ($c eq '"') { $in_d = 1; $cur .= $c; }
            elsif ($c =~ /[(\[{]/) { $depth++; $cur .= $c; }
            elsif ($c =~ /[)\]}]/) { $depth--; $cur .= $c; }
            elsif ($c eq ',' && $depth == 0) {
                push @args, _trim($cur);
                $cur = '';
            }
            else { $cur .= $c; }
        }
        return () if $in_s || $in_d || $depth != 0;   # unbalanced
        push @args, _trim($cur) if length _trim($cur);
        return @args;
    }

    sub _trim ($s) { $s =~ s/^\s+//; $s =~ s/\s+$//; return $s; }

    sub _trim_raw ($s) { my $t = $s; $t =~ s/\r?\n$//; return _trim($t); }
}
