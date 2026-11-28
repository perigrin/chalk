my %h = (a=>1,b=>2); %h = map { $_ => $h{$_} * 2 } keys %h; print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
