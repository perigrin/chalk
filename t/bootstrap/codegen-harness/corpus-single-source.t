# ABOUTME: Guard test ensuring the corpus has a single source of truth — every tag's source
# ABOUTME: in Harness::run_entry (via extract_snippet from the file) must match the corpus file.
use 5.42.0;
use utf8;

use Test2::V0;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness;
use Chalk::CodeGen::Harness::RunUnderPerl;

# ---------------------------------------------------------------------------
# This test asserts the single-source invariant:
#
#   For every tag known to Harness.pm, the snippet that run_entry feeds to
#   the oracle MUST equal the snippet that GapMap/extract_snippet pulls from
#   the corpus file.
#
# Failure means the two sources have drifted — run_entry and GapMap can
# silently feed different source to the oracle for the same tag, which is a
# trust-root integrity hole.
# ---------------------------------------------------------------------------

my $CORPUS_FILE = 't/fixtures/ir-audit-corpus.pl';

# Load the corpus file text (what GapMap/extract_snippet uses).
open my $fh, '<', $CORPUS_FILE
    or die "Cannot open '$CORPUS_FILE': $!";
local $/;
my $corpus_text = <$fh>;
close $fh;
ok(length($corpus_text) > 0, 'corpus file is non-empty');

# Enumerate all tags present in the corpus file (canonical set).
my @file_tags;
for my $line (split /\n/, $corpus_text) {
    if ($line =~ /^===\s+([A-Z]\d+)(?:\s|:)/) {
        push @file_tags, $1;
    }
}
ok(scalar(@file_tags) > 0, 'corpus file contains at least one tag');

# Build a lookup of what extract_snippet returns for each file tag.
my %file_source;
for my $tag (@file_tags) {
    my $snippet = eval {
        Chalk::CodeGen::Harness::RunUnderPerl->extract_snippet($corpus_text, $tag);
    };
    if ($@) {
        fail("extract_snippet failed for tag $tag: $@");
    } else {
        $file_source{$tag} = $snippet;
    }
}

# ---------------------------------------------------------------------------
# The single-source assertion: Harness->_corpus_snippet_for($tag) must equal
# the file source for every tag in the file.
#
# NOTE: Harness.pm does NOT yet expose a public accessor for the per-tag
# source it feeds to run_entry.  We test the property indirectly by checking
# that the Harness module no longer maintains a parallel %CORPUS hash.
#
# Until the implementation is refactored, we also provide a direct drift check:
# introspect the %CORPUS in Harness.pm against the file.  This is the RED
# phase — we expect at least F3 to fail.
# ---------------------------------------------------------------------------

# Read the raw Harness.pm source to extract the %CORPUS hash keys/values
# (before the refactor replaces it).
my $harness_pm = 't/lib/Chalk/CodeGen/Harness.pm';
open my $hfh, '<', $harness_pm
    or die "Cannot open '$harness_pm': $!";
my $harness_source = do { local $/; <$hfh> };
close $hfh;

# Parse out the %CORPUS entries: lines like:
#   TAG  => '...',
my %corpus_hash;
while ($harness_source =~ /^\s+([A-Z]\d+)\s*=>\s*'((?:[^'\\]|\\.)*)',\s*$/mg) {
    my ($tag, $val) = ($1, $2);
    # Un-escape backslash sequences in the single-quoted string.
    $val =~ s/\\'/'/g;
    $val =~ s/\\\\/\\/g;
    $corpus_hash{$tag} = $val;
}

my $has_corpus_hash = (%corpus_hash) ? 1 : 0;

# If the %CORPUS hash is gone (post-refactor), all tags resolve from the file
# and there is nothing to compare — the invariant holds trivially.
if (!$has_corpus_hash) {
    pass('Harness.pm has no parallel %CORPUS hash — single source of truth holds');
    done_testing;
    exit;
}

# Pre-refactor: compare %CORPUS against the file for every tag in the file.
# We expect F3 to differ; any other diffs are also reported.
my @drifted;
for my $tag (@file_tags) {
    next unless exists $corpus_hash{$tag};    # file-only tags are fine (not in %CORPUS)

    my $hash_val = $corpus_hash{$tag};
    my $file_val = $file_source{$tag};

    unless (defined $file_val) {
        push @drifted, { tag => $tag, reason => 'missing from file_source (extract failed)' };
        next;
    }

    unless ($hash_val eq $file_val) {
        push @drifted, {
            tag    => $tag,
            corpus => $hash_val,
            file   => $file_val,
        };
    }
}

# Also check for tags in %CORPUS that are NOT in the file.
my %file_tag_set = map { $_ => 1 } @file_tags;
my @corpus_only = grep { !exists $file_tag_set{$_} } sort keys %corpus_hash;

# Report drifted tags — this is the RED evidence.
for my $d (@drifted) {
    fail("DRIFT: tag $d->{tag} differs between %CORPUS and corpus file");
    if (exists $d->{corpus}) {
        diag("  %CORPUS: $d->{corpus}");
        diag("  file:    $d->{file}");
    } else {
        diag("  reason: $d->{reason}");
    }
}

# Tags only in %CORPUS (not in file) are also drift.
for my $tag (@corpus_only) {
    fail("CORPUS-ONLY: tag $tag exists in %CORPUS but not in corpus file");
    diag("  %CORPUS: $corpus_hash{$tag}");
}

# The single-source invariant passes only when there is zero drift.
is(scalar(@drifted),    0, 'zero tags have drifted source between %CORPUS and corpus file');
is(scalar(@corpus_only), 0, 'zero tags exist only in %CORPUS (not in corpus file)');

# Spot-check: F3 must be runnable (define sub foo) in the canonical (file) source.
my $f3_source = $file_source{F3};
ok(defined $f3_source, 'F3 is present in the corpus file');
if (defined $f3_source) {
    ok($f3_source =~ /\bsub\s+foo\b/,
        'corpus file F3 defines sub foo (runnable — calls foo(1,2) so foo must exist)');
}

done_testing;
