our $g=1; sub f { "@_" } print f($g, do { $g = 5; 6 }), "\n";
