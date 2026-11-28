my %h = (a=>1,b=>2,c=>3); delete @h{map { $_ } "b", "c"}; print join(",", keys %h), "\n";
