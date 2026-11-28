my %h = (a=>1,b=>2,c=>3); sub ks { qw(b c) } delete @h{ks()}; print join(",", keys %h), "\n";
