my %h = (a=>1,b=>2,c=>3); my @k = qw(b c); @h{@k} = (8, 9); print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
