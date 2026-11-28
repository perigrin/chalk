my $r = {a=>1}; { local $r->{n} = 8; print join(",", sort keys %$r) } print join(",", sort keys %$r), "\n";
