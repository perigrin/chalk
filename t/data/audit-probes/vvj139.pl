my %h; $h{1,2} = "x"; my ($k) = keys %h; print join("|", split /$;/, $k), "\n";
