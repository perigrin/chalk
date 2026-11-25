our $g=1; sub g2 { $g=9; 0 } sub f { "@_" } print f($g, g2()), "\n";
