our %h = (a=>1); { local %h = %h; $h{a} = 5; $h{b} = 6 } print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
