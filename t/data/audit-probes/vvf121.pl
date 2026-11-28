my $k = "a"; my %h; $h{$k} = $k++; print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
