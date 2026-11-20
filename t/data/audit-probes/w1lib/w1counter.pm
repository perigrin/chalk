# ABOUTME: Library code for the w1lib probes: a class in a lower-case module, which
# ABOUTME: B::SoN does not follow (a pragma's name) yet emits when the program calls it.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

class w1counter {
    field $step :param = 10;
    method bump { $w1counter::n += $step; return }
    method run {
        $w1counter::n = 0;
        for my $i (1..3) { $w1counter::n = $w1counter::n + 1; $self->bump; }
        return $w1counter::n;
    }
}
1;
