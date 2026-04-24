# ABOUTME: Test-only helpers for detecting and classifying ambiguity in Boolean parse results.
# ABOUTME: Walks Context trees produced by Boolean::add() and reports each ambiguous wrapper.
use 5.42.0;
use utf8;

package AmbiguityAnalysis;

use Exporter 'import';
our @EXPORT_OK = qw(ambiguity_sites classify_site);

use Scalar::Util qw(blessed refaddr);

# Walk a Boolean-parse result Context and return one hashref per
# ambiguous wrapper encountered. Each site is:
#   { context => $wrapper, left => $wrapper->children->[0], right => $wrapper->children->[1] }
# Walk order is pre-order: outer wrappers before inner ones. The
# walker descends into both ambiguous and non-ambiguous two-child
# nodes so ambiguity buried beneath structural multiply composition
# is still discovered. Non-Context inputs return an empty list.
#
# Context values form a DAG, not a tree — Earley and the semirings
# reuse Context objects across multiple parents. A %seen refaddr guard
# ensures each node is inspected at most once, so a shared ambiguous
# wrapper reported once regardless of how many paths reach it.
sub ambiguity_sites($root) {
    return () unless blessed($root) && $root->isa('Chalk::Bootstrap::Context');

    my @sites;
    my %seen;
    my @queue = ($root);
    while (@queue) {
        my $node = shift @queue;
        next unless blessed($node) && $node->isa('Chalk::Bootstrap::Context');
        next if $seen{refaddr($node)}++;

        if ($node->annotations->{ambiguous}) {
            my @kids = $node->children->@*;
            push @sites, {
                context => $node,
                left    => $kids[0],
                right   => $kids[1],
            };
        }

        # Descend into children whether this node was ambiguous or not —
        # ambiguity can nest, and non-ambiguous multiply nodes can contain
        # ambiguous descendants. unshift+shift gives pre-order: a node's
        # children are visited before its siblings' subtrees.
        unshift @queue, $node->children->@*;
    }
    return @sites;
}

# Shape-based classifier for an ambiguity site. Returns the name of
# the ambiguity class (from docs/architecture/ambiguity-classes.md)
# the site belongs to, or 'unknown' if the site does not match any
# documented class.
#
# This is a stub. Classification logic is driven by the corpus tests
# in t/bootstrap/grammar-ambiguity-corpus.t and added there via TDD.
sub classify_site($site) {
    return 'unknown';
}

true;
