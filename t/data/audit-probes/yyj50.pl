my %h; $h{1,2} = "x"; my ($k) = keys %h; print join("|", split /$;/, $k), exists $h{1,2} ? "y" : "n", "\n";
