our $g=1; sub f { "@_" } print f($g, local $g = 5), "\n";
