my %h=(a=>1); my %c=(%h, x=>1); delete $h{a}; print join(",", sort keys %c), "\n";
