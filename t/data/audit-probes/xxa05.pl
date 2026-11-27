sub f { $_[0] = "n" } my %h=(k=>"o"); f($h{k}); f($h{z}); print join(",", map {"$_=$h{$_}"} sort keys %h), "\n";
