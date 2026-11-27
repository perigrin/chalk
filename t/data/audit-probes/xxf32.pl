our %g = (a=>1); { local $g{a}; print exists $g{a} ? "e" : "n", defined $g{a} ? "d" : "u" } print $g{a}, "\n";
