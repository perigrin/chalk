my %h = map { $_ => 1 } 1..5; delete @h{2..4}; print join(",", sort keys %h), "\n";
