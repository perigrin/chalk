my $i = 0; my %h; $h{$i++} = $i; $h{$i} = $i++; print join(",", map {"$_=$h{$_}"} sort keys %h), "\n";
