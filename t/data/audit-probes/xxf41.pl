our %g = (a=>1,b=>2); { local @g{qw(a c)} = (8,9); print join(",", map {"$_$g{$_}"} sort keys %g) } print join(",", map {"$_$g{$_}"} sort keys %g), "\n";
