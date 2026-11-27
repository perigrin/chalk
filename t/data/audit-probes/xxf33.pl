our %g = (a=>1); eval { local $g{a} = 2; local $g{z} = 3; die "x\n" }; print join(",", map {"$_$g{$_}"} sort keys %g), "\n";
