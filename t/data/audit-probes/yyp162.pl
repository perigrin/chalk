our $g=1; sub f { "@_" } print f($g, $g++), f($g++, $g), "\n";
