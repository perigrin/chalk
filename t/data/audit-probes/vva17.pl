our %h = (a=>1,b=>2,c=>3); { local @h{qw(a b)}; print join(",", map { defined $h{$_} ? "d" : "u" } sort keys %h) } print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
