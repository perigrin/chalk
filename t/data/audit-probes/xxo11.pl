my $r = {a=>1}; { local @$r{qw(a b)} = (8,9); print join(",", sort keys %$r) } print join(",", map {"$_$r->{$_}"} sort keys %$r), "\n";
