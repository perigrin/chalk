our %h = (a=>1); { local $h{a} = 9; delete $h{a}; print exists $h{a} ? "e" : "n" } print $h{a}, "\n";
