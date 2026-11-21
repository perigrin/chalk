our $g = 0; sub f { $g = $_[0] + 1; $_[0] } print $g, f(1), "\n";
