our $g = 1; sub f { local $g = $g + 1; return g2() } sub g2 { local $g = $g * 10; $g } print f(), $g, "\n";
