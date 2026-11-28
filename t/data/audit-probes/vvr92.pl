my %h = (a=>1,b=>2,c=>3); my @k = qw(a b); $_ *= 2 for @h{@k}; print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
