our %h=(k=>1); sub f { local $h{k}=2; local $h{n}=3; g() } sub g { print join(",", map {"$_=$h{$_}"} sort keys %h), "\n" } f(); print join(",", map {"$_=$h{$_}"} sort keys %h), "\n";
