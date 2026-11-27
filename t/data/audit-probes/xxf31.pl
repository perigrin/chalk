our %g = (a=>1); { local $g{a} = 2; local $g{b} = 3; print join(",", map {"$_$g{$_}"} sort keys %g) } print join(",", map {"$_$g{$_}"} sort keys %g), "\n";
