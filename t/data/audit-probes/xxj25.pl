my %h = (a=>1,b=>2); for my $k (sort keys %h) { $h{$k}++; delete $h{b} if $k eq "a" } print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
