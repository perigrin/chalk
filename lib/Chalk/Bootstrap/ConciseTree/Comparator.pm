# ABOUTME: Structural comparison of ConciseTree objects with normalization.
# ABOUTME: Strips variable pad slots, nextstate details, and leave ref counts before comparing.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::ConciseOp;
use Chalk::Bootstrap::ConciseTree;

class Chalk::Bootstrap::ConciseTree::Comparator {

    # Compare two ConciseTrees structurally after normalization.
    # Returns { match => bool, differences => [...] }
    method compare($ours, $theirs) {
        my $norm_ours = $self->normalize($ours);
        my $norm_theirs = $self->normalize($theirs);

        my @differences;

        if ($norm_ours->op_count() != $norm_theirs->op_count()) {
            push @differences, sprintf(
                'Op count mismatch: ours=%d theirs=%d',
                $norm_ours->op_count(), $norm_theirs->op_count(),
            );
            return { match => false, differences => \@differences };
        }

        my $our_ops = $norm_ours->ops();
        my $their_ops = $norm_theirs->ops();

        for my $i (0 .. $norm_ours->op_count() - 1) {
            my $our_key = $our_ops->[$i]->structural_key();
            my $their_key = $their_ops->[$i]->structural_key();

            if ($our_key ne $their_key) {
                push @differences, sprintf(
                    'Op %d differs: ours=%s theirs=%s',
                    $i + 1, $our_key, $their_key,
                );
            }
        }

        return {
            match       => (scalar @differences == 0 ? true : false),
            differences => \@differences,
        };
    }

    # Normalize a ConciseTree by stripping variable-specific details.
    # Returns a new ConciseTree with normalized ops.
    method normalize($tree) {
        my @normalized_ops;

        for my $op ($tree->ops()->@*) {
            my $type_info = $op->type_info();

            if (defined $type_info) {
                # Strip pad slot numbers: $x:3,4 → $x
                $type_info =~ s/([\$\@\%]\w+):\d+,\d+/$1/g;

                # Strip nextstate details entirely
                if ($op->name() eq 'nextstate') {
                    $type_info = undef;
                }

                # Strip leave ref count: 1 ref → undef
                if ($op->name() eq 'leave') {
                    $type_info = undef;
                }

                # Strip targ numbers: t15 → undef (for aassign etc.)
                if (defined $type_info && $type_info =~ /^t\d+$/) {
                    $type_info = undef;
                }
            }

            # Strip branch target references: other->X, next->X, last->X, redo->X
            # These appear on branching ops (and, or, cond_expr) and loop
            # envelopes (enterloop, enteriter) as position-dependent labels.
            if (defined $type_info) {
                $type_info =~ s/\b(?:other|next|last|redo)->\w+//g;
                $type_info =~ s/\s+/ /g;
                $type_info =~ s/^\s+|\s+$//g;
                $type_info = undef if $type_info eq '';
            }

            my $private = $op->private();

            # Strip /REFC from leave private flags (ref count detail)
            if ($op->name() eq 'leave') {
                $private =~ s{/REFC}{};
                $private =~ s{^\s+|\s+$}{}g;
            }

            # Strip numeric private flags (/1, /2) — defensive against future
            # changes to Oracle parsing. Currently these end up in flags (not
            # private) due to Oracle's uppercase-only regex, but guard here too.
            $private =~ s{/\d+}{}g;

            # Strip /COMPOUND flag (internal marker for compound assignment ops)
            $private =~ s{/COMPOUND}{}g;

            $private =~ s{^\s+|\s+$}{}g;

            push @normalized_ops, Chalk::Bootstrap::ConciseOp->new(
                name      => $op->name(),
                arity     => $op->arity(),
                type_info => $type_info,
                flags     => '',       # flags are not structurally significant
                private   => $private,
            );
        }

        return Chalk::Bootstrap::ConciseTree->new(ops => \@normalized_ops);
    }
}
