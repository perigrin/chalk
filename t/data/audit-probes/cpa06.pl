our %h=(a=>1); our %c=%h; $c{a}=2; $h{b}=3; print join(",", map {"$_=$h{$_}"} sort keys %h), ";", join(",", map {"$_=$c{$_}"} sort keys %c), "\n";
