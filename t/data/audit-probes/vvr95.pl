my %h = (a=>1,b=>2,c=>3); $_ *= 2 for @h{sort keys %h}; print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
