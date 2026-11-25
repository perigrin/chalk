my %h=(a=>1); for my $k (keys %h) { $h{$k . "x"} = 2 } print join(",", sort keys %h), "\n";
