my %h = (k => "ab"); for my $k (keys %h) { $k .= "z" } print join(",", keys %h), "\n";
