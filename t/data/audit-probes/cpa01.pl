my %h=(a=>1,b=>2); my %c=%h; $c{a}=9; delete $c{b}; $h{c}=3; print join(",", map {"$_=$h{$_}"} sort keys %h), ";", join(",", map {"$_=$c{$_}"} sort keys %c), "\n";
