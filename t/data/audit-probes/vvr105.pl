my %h = (a=>1,b=>2,c=>3); my @k = qw(b c); delete @h{@k[0,1]}; print join(",", keys %h), "\n";
