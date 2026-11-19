my %h; for my $i (1..5) { next if $i % 2; $h{$i} = $i * 2 } print join(",", map {"$_=$h{$_}"} sort keys %h), "\n";
