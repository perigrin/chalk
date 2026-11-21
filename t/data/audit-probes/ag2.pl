use feature "say"; our $g = 0; sub f { $g = $_[0] + 1; $_[0] } say f(1), $g, f(0), $g;
