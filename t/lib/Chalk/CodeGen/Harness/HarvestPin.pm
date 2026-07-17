# ABOUTME: Reproducibility guardrail — single source of truth for the perl5-blead
# ABOUTME: SHA the harvester corpus is sourced from, plus a LOUD drift-detecting verify.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

# The pinned perl5 blead SHA the harvester corpus is (re)harvested against.
# This is the ONE place the pin is recorded. A corpus harvested against an
# unpinned/moving Perl is a corrupted oracle, so re-harvest is gated on this
# SHA matching the ~/dev/perl5 checkout HEAD.
#
# Decision (regenerate-gated-on-SHA): the corpus does not exist yet, so we do
# NOT vendor Perl's t/ into this repo. Instead a future harvest run must call
# verify_checkout() first and REFUSE to proceed unless the checkout is at this
# pin with a clean tree. verify_checkout only VERIFIES — it never regenerates
# or mutates the checkout. Re-harvest is a deliberate, separate act.
class Chalk::CodeGen::Harness::HarvestPin {

    # pinned_sha() as a class method, so callers need no instance. This is the
    # single source of truth for the pinned SHA.
    sub pinned_sha ($class) { '94e5086608' }

    # verify_checkout($perl5_path, expected_sha => $sha)
    #
    # Verifies (never mutates) that the perl5 checkout at $perl5_path is at the
    # pinned SHA with a clean working tree. $expected_sha defaults to the pin.
    #
    # Returns a hashref { status => ..., loud => bool, detail => $str } where
    # status is one of:
    #   'ok'       — HEAD matches the pin and the tree is clean (loud = false)
    #   'mismatch' — HEAD is a DIFFERENT SHA (loud; detail names both SHAs)
    #   'absent'   — the checkout does not exist / is not a git repo (loud)
    #   'dirty'    — `git status --porcelain` is non-empty (loud; do NOT harvest)
    sub verify_checkout ($class, $path, %opt) {
        my $expected = $opt{expected_sha} // $class->pinned_sha;

        return { status => 'absent', loud => 1,
                 detail => "perl5 checkout absent: $path" }
            unless defined $path && -d $path;

        my $head = qx{git -C \Q$path\E rev-parse HEAD 2>/dev/null};
        chomp $head;
        return { status => 'absent', loud => 1,
                 detail => "not a git checkout: $path" }
            unless length $head;

        # A prefix match honors the abbreviated pin (94e5086608...).
        unless (index($head, $expected) == 0 || index($expected, $head) == 0) {
            return { status => 'mismatch', loud => 1,
                     detail => "perl5 HEAD $head != pinned $expected -- "
                             . "corpus oracle would be corrupted; re-pin or "
                             . "checkout $expected before harvesting" };
        }

        my $porcelain = qx{git -C \Q$path\E status --porcelain 2>/dev/null};
        return { status => 'dirty', loud => 1,
                 detail => "perl5 checkout $path is dirty -- refusing to "
                         . "harvest from an uncommitted tree" }
            if length $porcelain;

        return { status => 'ok', loud => 0,
                 detail => "perl5 checkout $path at pinned $expected, clean" };
    }
}
