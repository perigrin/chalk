sub f { my ($p) = @_; g2(); $p } sub g2 { $main::x = 9 } our $x = 1; print f($x), $x, "\n";
