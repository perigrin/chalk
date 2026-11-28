my %h = (a=>1,b=>2); sub f { $_[0] .= "x" } f($h{$_}) for sort keys %h; print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
