my %h = (a=>1,b=>2); my %i = reverse %h; my @p = %h; print join(",", map {"$_$i{$_}"} sort keys %i), scalar(@p), "\n";
