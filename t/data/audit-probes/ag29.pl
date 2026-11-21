my %h = (k => 0); sub f { $h{k} = $_[0] + 1; $_[0] } print f(1), $h{k}, f(0), $h{k}; print "\n";
