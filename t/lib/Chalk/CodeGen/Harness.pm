# ABOUTME: Top-level CodeGen harness rig — runs one corpus entry end-to-end (S via oracle, P via driver).
# ABOUTME: run_entry($tag, $spec) -> { S, P, verdict } using RunUnderPerl, PerlDriver, and Comparator.
package Chalk::CodeGen::Harness;

use 5.42.0;
use utf8;

use Carp qw(croak);

use Chalk::CodeGen::Harness::HandGraphs;
use Chalk::CodeGen::Harness::RunUnderPerl;
use Chalk::CodeGen::Harness::PerlDriver;
use Chalk::CodeGen::Harness::Comparator;

# Path to the === TAG-delimited corpus file.  This is the single source of
# truth for all corpus snippets — both run_entry (S side) and GapMap
# (extract_snippet) derive from the same file.
my $CORPUS_FILE = 't/fixtures/ir-audit-corpus.pl';

# _corpus_text() -> $text
# Loads the corpus file and returns its full text.  Dies if the file is
# missing or empty.  Called once per run_entry invocation; caching is not
# needed because the harness is not on a hot path.
my $_corpus_cache;
sub _corpus_text {
    return $_corpus_cache if defined $_corpus_cache;
    open my $fh, '<', $CORPUS_FILE
        or croak "Harness: cannot open corpus '$CORPUS_FILE': $!";
    local $/;
    my $text = <$fh>;
    close $fh;
    croak "Harness: corpus file is empty" unless defined $text && length $text;
    $_corpus_cache = $text;
    return $text;
}

# _known_tags() -> %tag_set
# Returns a set (hash with 1 values) of all tags present in the corpus file.
my %_known_tags_cache;
my $_known_tags_loaded = 0;
sub _known_tags {
    unless ($_known_tags_loaded) {
        my $text = _corpus_text();
        for my $line (split /\n/, $text) {
            if ($line =~ /^===\s+([A-Z]\d+)(?:\s|:)/) {
                $_known_tags_cache{$1} = 1;
            }
        }
        $_known_tags_loaded = 1;
    }
    return %_known_tags_cache;
}

# run_entry($tag, $spec) -> { S => BehaviorRecord, P => BehaviorRecord, verdict => \%verdict }
#
# Runs one corpus entry end-to-end:
#   1. S = RunUnderPerl->capture(corpus snippet for $tag, $spec)  — oracle via real perl
#   2. P = PerlDriver->run(HandGraphs->graph_for($tag), $spec)    — generated via Chalk
#   3. verdict = Comparator->verdict($S, $P, $emission_meta)
#
# Returns a hashref with keys S, P, verdict.
# Dies if $tag is not a known corpus entry.
sub run_entry {
    my (undef, $tag, $spec) = @_;    # undef = class name
    croak "run_entry: tag must be a non-empty string"
        unless defined $tag && length $tag;
    croak "run_entry: spec must be a hashref"
        unless ref $spec eq 'HASH';

    my %tags = _known_tags();
    croak "run_entry: unknown tag '$tag'"
        unless exists $tags{$tag};

    my $snippet = Chalk::CodeGen::Harness::RunUnderPerl->extract_snippet(
        _corpus_text(), $tag
    );

    # ---- S side: oracle via real perl ----
    my $is_sub_spec = exists $spec->{sub_name};
    my $S = $is_sub_spec
        ? Chalk::CodeGen::Harness::RunUnderPerl->capture_sub($snippet, $spec)
        : Chalk::CodeGen::Harness::RunUnderPerl->capture($snippet, $spec);

    # ---- P side: generated via Chalk Target::Perl ----
    my $graph = Chalk::CodeGen::Harness::HandGraphs->graph_for($tag);
    my ($P, $emission_meta) = Chalk::CodeGen::Harness::PerlDriver->run($graph, $spec);

    # ---- Verdict ----
    $emission_meta->{graph_source} //= "hand:$tag";
    my $verdict = Chalk::CodeGen::Harness::Comparator->verdict($S, $P, $emission_meta);

    return {
        S       => $S,
        P       => $P,
        verdict => $verdict,
    };
}

1;
