our %h = (a=>1); { local %h = (b=>2); delete $h{b}; } print join(",", keys %h), "\n";
