# ABOUTME: Library code for probe w1lib4: a class in a lower-case module (not followed,
# ABOUTME: emitted when called) whose method is the only writer of a package scalar.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

class w1step {
    field $step :param = 10;
    method bump { $w1step::n += $step; return }
}
1;
