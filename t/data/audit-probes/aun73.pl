our %h=(a=>1); sub t { local $h{a} = 2; die "x\n" } eval { t() }; print "$h{a}\n";
