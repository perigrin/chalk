my %h = (a=>1,b=>2,c=>3); my @k = qw(b c); my @d = delete @h{@k}; print "@d|", join(",", keys %h), "\n";
