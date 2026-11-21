our $g = 0; sub f { $g = $_[0] + 1; $_[0] } sub h { join ",", @_ } print h(f(1), $g, f(0), $g), "\n";
