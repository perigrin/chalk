my %c; $c{$_}++ for qw(a b a c a); print join(",", map {"$_$c{$_}"} sort keys %c), "\n";
