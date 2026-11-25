our $g=1; sub f { "@_" } sub k { $g++ } print f($g, k(), $g, k()), "\n";
