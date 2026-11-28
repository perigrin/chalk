my %h = (a=>1,b=>2); sub f { $_[0] .= "x" } for my $x (values %h) { f($x) } print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
