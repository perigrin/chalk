our %h=(a=>1); my %c=%h; sub w { $h{b}=2 } w(); print join(",", sort keys %c), "\n";
