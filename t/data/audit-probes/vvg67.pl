my %c; $c{$_}{n}++ for qw(a b a); print join(",", map {"$_$c{$_}{n}"} sort keys %c), "\n";
