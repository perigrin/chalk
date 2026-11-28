our %h = (a=>1); for my $i (1..2) { local %h = (i => $i); print $h{i} } print join(",", keys %h), "\n";
