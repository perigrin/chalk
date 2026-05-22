# ABOUTME: Audit tool — scans lib/**.pm for Perl constructs and compares against the audit corpus.
# ABOUTME: Output: per-category counts and a list of construct patterns present in lib/ but absent from corpus.
use 5.42.0;
use utf8;
use File::Find;

# Categories the audit corpus exercises. For each category, a regex
# that conservatively detects the construct in source. False positives
# are acceptable (over-counting), false negatives are not (missing a
# construct entirely).
my %CATEGORIES = (
    # Variable declarations
    'my-scalar'                 => qr/\bmy\s+\$\w+/,
    'my-array'                  => qr/\bmy\s+\@\w+/,
    'my-hash'                   => qr/\bmy\s+\%\w+/,
    'our'                       => qr/\bour\s+[\$\@\%]\w+/,
    'state'                     => qr/\bstate\s+[\$\@\%]\w+/,
    'local'                     => qr/\blocal\s+[\$\@\%]\w+/,
    'my-multiple'               => qr/\bmy\s+\([^)]+\)/,
    'field'                     => qr/^\s*field\s+[\$\@\%]\w+/m,

    # Bare statement calls (side-effects only)
    'bare-push'                 => qr/^\s*push\s+/m,
    'bare-unshift'              => qr/^\s*unshift\s+/m,
    'bare-pop'                  => qr/^\s*pop\s+/m,
    'bare-shift'                => qr/^\s*shift\s+/m,
    'bare-print'                => qr/^\s*print\b/m,
    'bare-say'                  => qr/^\s*say\b/m,
    'bare-warn'                 => qr/^\s*warn\b/m,
    'bare-die'                  => qr/^\s*die\b/m,
    'bare-croak'                => qr/^\s*croak\b/m,
    'bare-carp'                 => qr/^\s*carp\b/m,
    'bare-method-call'          => qr/^\s+\$\w+->\w+\s*\(/m,
    'bare-function-call'        => qr/^\s+[a-z_][a-zA-Z0-9_]+\s*\(/m,
    'bare-splice'               => qr/^\s*splice\s+/m,
    'bare-delete'               => qr/^\s*delete\s+/m,

    # Assignments
    'assign-scalar'             => qr/^\s*\$\w+\s*=\s*[^=]/m,
    'assign-array-elem'         => qr/\$\w+\[[^\]]+\]\s*=\s*[^=]/,
    'assign-hash-elem'          => qr/\$\w+\{[^\}]+\}\s*=\s*[^=]/,
    'compound-assign-plus'      => qr/[\$\@\%]\w+(?:->[\@\%\$]\*?)*\s*\+=/,
    'compound-assign-concat'    => qr/\$\w+\s*\.=/,
    'compound-assign-min'       => qr/[\$\@\%]\w+\s*-=/,
    'compound-assign-or'        => qr/\$\w+\s*\/\/=/,
    'pre-inc'                   => qr/\+\+\$\w+/,
    'post-inc'                  => qr/\$\w+\+\+/,
    'pre-dec'                   => qr/--\$\w+/,
    'post-dec'                  => qr/\$\w+--/,

    # Control flow
    'if'                        => qr/\bif\s*\(/,
    'unless'                    => qr/\bunless\s*\(/,
    'elsif'                     => qr/\belsif\s*\(/,
    'else'                      => qr/\belse\s*\{/,
    'while'                     => qr/\bwhile\s*\(/,
    'until'                     => qr/\buntil\s*\(/,
    'foreach'                   => qr/\bforeach\s+/,
    'for-c-style'               => qr/\bfor\s*\([^)]*;[^)]*;/,
    'for-as-foreach'            => qr/\bfor\s+(?:my\s+)?[\$\@\%]\w+/,
    'postfix-if'                => qr/^[^\n#]+\bif\s+[^{]+;/m,
    'postfix-unless'            => qr/^[^\n#]+\bunless\s+[^{]+;/m,
    'postfix-while'             => qr/^[^\n#]+\bwhile\s+[^{]+;/m,
    'postfix-for'               => qr/^[^\n#]+\bfor(?:each)?\s+/m,
    'ternary'                   => qr/\?\s*[^:]+\s*:/,
    'try-catch'                 => qr/\btry\s*\{/,
    'finally'                   => qr/\bfinally\s*\{/,

    # Return/die patterns
    'return-bare'               => qr/^\s*return\b/m,
    'die-with-message'          => qr/\bdie\s+["']/,
    'die-with-hashref'          => qr/\bdie\s+\{/,

    # Calls
    'method-call'               => qr/\$\w+->\w+/,
    'chained-method-call'       => qr/->\w+\([^)]*\)->\w+/,
    'static-method-call'        => qr/\w+::\w+\s*\(/,
    'function-call'             => qr/\b[a-z_]\w+\s*\(/,
    'method-call-no-parens'     => qr/\$\w+->\w+(?!\s*\()/,

    # Deref / subscript
    'postfix-deref-array'       => qr/->\@\*/,
    'postfix-deref-hash'        => qr/->\%\*/,
    'postfix-deref-scalar'      => qr/->\$\*/,
    'arrow-subscript-array'     => qr/->\[/,
    'arrow-subscript-hash'      => qr/->\{/,
    'subscript-array'           => qr/\$\w+\[[^\]]+\]/,
    'subscript-hash'            => qr/\$\w+\{[^\}]+\}/,
    'slice-array'               => qr/\@\w+\[[^\]]+\]/,
    'slice-hash'                => qr/\@\w+\{[^\}]+\}/,

    # Block builtins
    'map-block'                 => qr/\bmap\s*\{/,
    'grep-block'                => qr/\bgrep\s*\{/,
    'sort-block'                => qr/\bsort\s*\{/,
    'sort-bare'                 => qr/\bsort\s+\w/,
    'anonymous-sub'             => qr/\bsub\s*[(\s]/,
    'sub-with-sig'              => qr/\bsub\s+\w+\s*\(/,

    # Phasers / declarations
    'class'                     => qr/^class\s+/m,
    'method'                    => qr/^\s*method\s+\w+/m,
    'top-level-sub'             => qr/^sub\s+\w+/m,
    'my-sub'                    => qr/\bmy\s+sub\s+\w+/,
    'ADJUST'                    => qr/\bADJUST\s*\{/,
    'BEGIN'                     => qr/\bBEGIN\s*\{/,
    'END'                       => qr/\bEND\s*\{/,
    'INIT'                      => qr/\bINIT\s*\{/,
    'CHECK'                     => qr/\bCHECK\s*\{/,
    'UNITCHECK'                 => qr/\bUNITCHECK\s*\{/,

    # Regex
    'regex-match'               => qr/=~\s*\//,
    'regex-substitution'        => qr/=~\s*s[\/\{\(]/,
    'regex-transliteration'     => qr/=~\s*(?:tr|y)[\/\{\(]/,
    'regex-bind-not'            => qr/!~\s*\//,
    'qw-literal'                => qr/\bqw[\s(\[\{<]/,

    # Booleans / operators
    'logical-and'               => qr/\s&&\s/,
    'logical-or'                => qr/\s\|\|\s/,
    'defined-or'                => qr/\s\/\/\s/,
    'not'                       => qr/^\s*!\$/m,
    'string-concat'             => qr/\.\s*"/,

    # Refs / blessed
    'arrayref-literal'          => qr/\[[^\]]*\]/,
    'hashref-literal'           => qr/\{[^{}]*=>/,
    'bless'                     => qr/\bbless\b/,
    'ref-of'                    => qr/\\[\$\@\%]\w+/,

    # Strings / interpolation
    'string-interp'             => qr/"[^"]*\$\w+[^"]*"/,
    'heredoc'                   => qr/<<["']?[A-Z_]+/,

    # Pragmas / imports
    'use-pragma'                => qr/^\s*use\s+(?:strict|warnings|utf8|feature|experimental)\b/m,
    'use-module'                => qr/^\s*use\s+[A-Z]\w+/m,
    'no-pragma'                 => qr/^\s*no\s+/m,
    'require'                   => qr/^\s*require\b/m,

    # File / I/O
    'open'                      => qr/\bopen\s+/,
    'close'                     => qr/\bclose\s+/,
    'readline'                  => qr/<\$\w+>/,
    'local-rs'                  => qr/\blocal\s+\$\//,

    # Misc
    'eval-block'                => qr/\beval\s*\{/,
    'eval-string'               => qr/\beval\s+["']/,
    'do-block'                  => qr/\bdo\s*\{/,
    'wantarray'                 => qr/\bwantarray\b/,
    'caller'                    => qr/\bcaller\s*\(?/,
    'goto'                      => qr/\bgoto\s+/,
    'last-bare'                 => qr/^\s*last\s*;/m,
    'next-bare'                 => qr/^\s*next\s*;/m,
    'redo-bare'                 => qr/^\s*redo\s*;/m,
);

# Categories the audit corpus covers. From t/fixtures/ir-audit-corpus.pl.
my %CORPUS_COVERS = map { $_ => 1 } qw(
    my-scalar my-array my-hash field
    bare-push bare-unshift bare-print bare-say bare-warn bare-die bare-method-call bare-function-call
    assign-scalar assign-array-elem assign-hash-elem
    compound-assign-plus compound-assign-concat pre-inc post-inc
    if elsif else while foreach postfix-if postfix-while ternary try-catch
    return-bare die-with-message
    method-call chained-method-call function-call
    postfix-deref-array postfix-deref-hash subscript-array subscript-hash
    map-block grep-block sort-bare anonymous-sub sub-with-sig
    class method top-level-sub my-sub ADJUST
    regex-match regex-substitution qw-literal
    logical-and logical-or defined-or not
    arrayref-literal hashref-literal
);

# Walk lib/ and count occurrences of each category.
my %counts;
my %sample_files;  # category => arrayref of (file, line, snippet)

find(sub {
    return unless -f && /\.pm$/;
    my $path = $File::Find::name;
    open my $fh, '<:utf8', $_ or return;
    my $content = do { local $/; <$fh> };
    close $fh;

    my @lines = split /\n/, $content;
    for my $cat (sort keys %CATEGORIES) {
        my $re = $CATEGORIES{$cat};
        my $matched = 0;
        # Scan whole-file for the regex; collect first match line for sampling.
        if ($content =~ $re) {
            # Find first line containing the match for samples.
            for my $i (0..$#lines) {
                if ($lines[$i] =~ $re) {
                    $counts{$cat}++;
                    if (!$sample_files{$cat} || @{$sample_files{$cat}} < 3) {
                        my $snippet = $lines[$i];
                        $snippet =~ s/^\s+//;
                        $snippet = substr($snippet, 0, 80);
                        push $sample_files{$cat}->@*, "$path:" . ($i+1) . " :: $snippet";
                    }
                    $matched = 1;
                    last;
                }
            }
            # Also count files matching (not just first occurrence)
            if (!$matched) {
                # File-level match but no line found (multiline regex etc.) — still credit
                $counts{$cat}++;
            }
        }
    }
}, 'lib');

# Print report.
my $W = 36;

say "## Category counts in lib/*.pm";
say "(file-presence count: how many .pm files contain the construct)";
say "";
say sprintf("%-${W}s %-8s %-10s %s", 'category', 'files', 'corpus?', 'sample');
say "-" x 100;

my @sorted = sort { ($counts{$b} // 0) <=> ($counts{$a} // 0) || $a cmp $b } keys %CATEGORIES;
for my $cat (@sorted) {
    my $n = $counts{$cat} // 0;
    my $covered = $CORPUS_COVERS{$cat} ? 'yes' : 'NO';
    my $samp = ($sample_files{$cat} && $sample_files{$cat}->[0]) // '';
    $samp = substr($samp, 0, 80);
    say sprintf("%-${W}s %-8d %-10s %s", $cat, $n, $covered, $samp);
}

say "";
say "## Gaps (constructs present in lib/ but absent from corpus)";
say "";
my @gaps = grep { ($counts{$_} // 0) > 0 && !$CORPUS_COVERS{$_} } sort keys %CATEGORIES;
my @real_gaps;
for my $cat (@gaps) {
    push @real_gaps, [$cat, $counts{$cat}, ($sample_files{$cat} // [])->[0] // ''];
}
@real_gaps = sort { $b->[1] <=> $a->[1] } @real_gaps;
say sprintf("%-${W}s %-8s %s", 'category', 'files', 'sample');
say "-" x 100;
for my $g (@real_gaps) {
    say sprintf("%-${W}s %-8d %s", $g->[0], $g->[1], substr($g->[2], 0, 80));
}

say "";
say "## Constructs in corpus but absent from lib/ (corpus-only patterns)";
say "";
for my $cat (sort keys %CORPUS_COVERS) {
    next if $counts{$cat};
    say "  $cat";
}
