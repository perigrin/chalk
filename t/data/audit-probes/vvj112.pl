my %h = (a=>1,b=>2,c=>3); my @d = delete @h{qw(a b)}; print "@d|", join(",", keys %h), "\n";
