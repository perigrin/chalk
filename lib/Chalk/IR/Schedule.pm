# ABOUTME: Ordered linear sequence of Chalk::IR::Schedule::Item entries produced by a scheduler.
# ABOUTME: Codegen consumes this; structured control is encoded as matched block_open/block_close pairs.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::IR::Schedule::Item;

class Chalk::IR::Schedule {
    field $items :param :reader = [];

    # Open/close balance property: every block_open has a matching
    # block_close of the same form, with else/elsif/catch only appearing
    # between matched pairs. Returns true iff the schedule is well-formed.
    method is_balanced() {
        my @stack;
        for my $item ($items->@*) {
            my $kind = $item->kind;
            if ($kind eq 'block_open') {
                push @stack, $item->form;
            } elsif ($kind eq 'block_close') {
                return false unless @stack;
                my $top = pop @stack;
                return false unless defined $top && defined $item->form
                    && $top eq $item->form;
            } elsif ($kind eq 'else' || $kind eq 'elsif' || $kind eq 'catch') {
                # Interior markers — must be inside some open block.
                return false unless @stack;
            }
            # 'stmt' is unconditionally legal.
        }
        return scalar(@stack) == 0;
    }
}
