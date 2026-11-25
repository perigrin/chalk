our $g=1; sub f { "@_" } print f($g, sub { $g++ }->()), "\n";
