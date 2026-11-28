my %h = (a=>1); sub d { die "x\n" } eval { $h{b}{c} = d() }; print join(",", sort keys %h), "\n";
