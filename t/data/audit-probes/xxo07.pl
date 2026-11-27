our %g = (a=>1); { local ($g{a}, $g{z}) = (8,9); print join(",", sort keys %g) } print join(",", map {"$_$g{$_}"} sort keys %g), "\n";
