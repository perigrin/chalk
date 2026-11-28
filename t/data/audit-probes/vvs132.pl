sub f { return (1, 2) } my %h = (a => f(), b => 1); print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
