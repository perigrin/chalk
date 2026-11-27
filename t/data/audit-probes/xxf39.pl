our %g = (a=>1); for my $k (qw(a b)) { local $g{$k} = 9; print join(",", sort keys %g), ";" } print join(",", sort keys %g), "\n";
