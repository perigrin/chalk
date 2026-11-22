my %h=(a=>1,b=>2); $_ *= 2 for values %h; print join(",", map {$h{$_}} sort keys %h), "\n";
