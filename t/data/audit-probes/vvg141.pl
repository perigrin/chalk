my $r = [1,2,3]; my %s = %$r[0,1]; print join(",", map {"$_$s{$_}"} sort keys %s), "\n";
