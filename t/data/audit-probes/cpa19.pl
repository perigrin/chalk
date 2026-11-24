my %h=(a=>1); my %c=%h; delete $h{a}; print exists $c{a} ? "y":"n", " ", scalar(keys %c), "\n";
