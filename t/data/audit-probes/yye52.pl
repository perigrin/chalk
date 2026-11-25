our %g=(a=>1); sub f { "@_" } print f($g{a}, $g{a}++), "\n";
