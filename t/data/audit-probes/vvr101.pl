my %h = (a=>1,b=>2,c=>3); delete @h{grep { $_ ne "a" } keys %h}; print join(",", keys %h), "\n";
