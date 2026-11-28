my %h = (a=>1,b=>2); my %m = (%h, b=>3, c=>4); print join(",", map {"$_$m{$_}"} sort keys %m), "\n";
