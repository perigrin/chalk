# ABOUTME: Scans lib/ for regex constructs and classifies each by the feature
# ABOUTME: it needs, to scope the atom-list-vs-graph regex rewrite decision.
use v5.42.0;
use utf8;
no warnings 'experimental';

# We classify by extracting the regex OPERATOR + pattern text from source, then
# testing the pattern text for feature markers. This is source-level (not
# optree-level) so it is a heuristic — but the classification buckets are what
# scope the rewrite, and we want the pattern TEXT which the optree precomp also
# carries verbatim. We deliberately scan the whole lib/ tree.

my @files;
require File::Find;
File::Find::find(sub { push @files, $File::Find::name if /\.pm$/ }, 'lib');
@files = sort @files;

# Feature buckets. Each pattern can hit multiple; we tally per-feature AND
# compute a per-pattern "verdict": does the CURRENT atom-list compiler lower it?
my %feat;              # feature -> count of patterns using it
my %feat_files;        # feature -> set of files
my $total = 0;
my $lowerable_now = 0; # patterns using ONLY currently-supported features
my $blocked = 0;
my %blocked_by;        # first blocking feature -> count (what to build first)
my %op_count;          # =~ / !~ / s/// / qr//
my @examples;          # a few blocked examples per feature

# Currently-supported feature slice (from _compile_regex_pattern, verified):
#   literals, . , char classes [..] incl ranges & negation, \d \w \s \D \W \S
#   as standalone atoms, ^ $ anchors, quantifiers * + ? {n,m} on SINGLE atoms,
#   groups (?:..) and (..) UNQUANTIFIED, byte escapes \t\n\r\f\a\e\0 \xHH.
# Blocking features (each dies GAP today):
sub classify_pattern ($pat, $flags, $op) {
    my @blockers;

    # Flags: any flag at all blocks (one gate covers all).
    push @blockers, "flags:/$flags" if length $flags;

    # Alternation | (not escaped, not in a class). Rough: a | that is not \|.
    # Strip escaped pipes and char-class contents first to avoid false hits.
    my $scan = $pat;
    $scan =~ s/\\.//g;                 # drop escaped chars
    (my $noclass = $scan) =~ s/\[[^\]]*\]//g;  # drop [..] contents
    push @blockers, "alternation" if $noclass =~ /\|/;

    # Quantified group:  ) immediately followed by * + ? {  (after escape-strip)
    push @blockers, "quantified-group" if $noclass =~ /\)[*+?{]/;

    # Non-greedy / lazy:  *? +? ??  {..}?
    push @blockers, "non-greedy" if $noclass =~ /[*+?}]\?/;

    # Assertion escapes \b \B \A \z \Z \G  and \p \N \c  and named \k \g
    push @blockers, "assertion-escape" if $pat =~ /\\[bBAzZGpNckg]/;

    # Lookaround / inline-modifier / code groups (?= (?! (?<= (?<! (?i) (?{
    push @blockers, "extended-group" if $pat =~ /\(\?[^:]/;

    # Backreference \1.. or \g{
    push @blockers, "backref" if $pat =~ /\\[1-9]/;

    # Mid-pattern anchor ^ or $ not at the very ends (approx).
    my $mid = $pat;
    $mid =~ s/^\^//; $mid =~ s/\$$//;
    push @blockers, "mid-anchor" if $mid =~ /(?<!\\)[\^\$]/;

    return @blockers;
}

for my $file (@files) {
    open my $fh, '<:encoding(UTF-8)', $file or next;
    local $/;
    my $src = <$fh>;
    close $fh;

    # Match the common operator forms with a / delimiter. This misses {} or
    # other delimiters and interpolated patterns — flagged in the doc as scan
    # limits. We capture: (op)(pattern)(flags).
    #   $x =~ /pat/flags   ,  $x =~ m/pat/flags  ,  $x !~ /pat/flags
    #   =~ s/pat/repl/flags , qr/pat/flags
    while ($src =~ m{
        (?<op> =~ \s* | !~ \s* )
        (?: m )?
        /
        (?<pat> (?: \\. | [^/\\] )* )
        /
        (?<flags> [a-z]* )
    }gx) {
        my ($op, $pat, $flags) = ($+{op}, $+{pat}, $+{flags});
        $op =~ s/\s+//g;
        $total++;
        $op_count{$op}++;
        my @b = classify_pattern($pat, $flags, $op);
        if (@b) {
            $blocked++;
            $blocked_by{$b[0]}++;
            for my $bf (@b) { $feat{$bf}++; $feat_files{$bf}{$file}++ }
            push @{$examples[0]{$b[0]} //= []}, "$file: /$pat/$flags"
                if @{$examples[0]{$b[0]} // []} < 3;
        } else {
            $lowerable_now++;
        }
    }
    # s/// and qr// separately (different delimiters/structure)
    while ($src =~ m{ \b s / (?<pat>(?:\\.|[^/\\])*) / (?:\\.|[^/\\])* / (?<flags>[a-z]*) }gx) {
        my ($pat,$flags) = ($+{pat}, $+{flags});
        $total++; $op_count{'s///'}++;
        my @b = classify_pattern($pat, $flags, 's///');
        # s/// ALSO blocks on /g /e /r etc. — flags already covers /g.
        if (@b) { $blocked++; $blocked_by{$b[0]}++; for my $bf (@b){$feat{$bf}++;$feat_files{$bf}{$file}++} }
        else    { $lowerable_now++ }
    }
    while ($src =~ m{ \b qr / (?<pat>(?:\\.|[^/\\])*) / (?<flags>[a-z]*) }gx) {
        my ($pat,$flags) = ($+{pat}, $+{flags});
        $total++; $op_count{'qr//'}++;
        my @b = classify_pattern($pat, $flags, 'qr//');
        if (@b) { $blocked++; $blocked_by{$b[0]}++; for my $bf (@b){$feat{$bf}++;$feat_files{$bf}{$file}++} }
        else    { $lowerable_now++ }
    }
}

say "# Regex feature scan over lib/ (", scalar(@files), " files)";
say "";
say "Total regex sites scanned (/-delimited): $total";
say "  by operator:";
say sprintf("    %-8s %d", $_, $op_count{$_}) for sort keys %op_count;
say "";
say sprintf("Lowerable NOW (only supported features): %d  (%.0f%%)", $lowerable_now, 100*$lowerable_now/($total||1));
say sprintf("Blocked by >=1 unsupported feature:      %d  (%.0f%%)", $blocked, 100*$blocked/($total||1));
say "";
say "## Blocked patterns by FIRST blocker (what to build first, by impact):";
for my $f (sort { $blocked_by{$b} <=> $blocked_by{$a} } keys %blocked_by) {
    say sprintf("    %-18s %3d patterns", $f, $blocked_by{$f});
}
say "";
say "## Feature usage (any occurrence, patterns may double-count) + file spread:";
for my $f (sort { $feat{$b} <=> $feat{$a} } keys %feat) {
    my $nf = scalar keys %{$feat_files{$f}};
    say sprintf("    %-18s %3d patterns across %2d files", $f, $feat{$f}, $nf);
}
say "";
say "## A few blocked examples (first blocker):";
for my $f (sort keys %{$examples[0] // {}}) {
    say "  [$f]";
    say "    $_" for @{$examples[0]{$f}};
}
