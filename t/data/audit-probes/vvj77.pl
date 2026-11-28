my @a = (1,2,3); my %i; @i{@a} = (0..$#a); print join(",", map {"$_$i{$_}"} sort keys %i), "\n";
