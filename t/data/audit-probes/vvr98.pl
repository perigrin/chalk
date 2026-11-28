my %h = (a=>1,b=>2,c=>3); delete @h{qw(b c)}; print join(",", keys %h), "\n";
