my %h; { local $; = "-"; $h{1,2} = 1 } print join(",", keys %h), "\n";
