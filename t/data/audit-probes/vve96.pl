my %h = (k=>1); sub f { $h{k} = 5; $_[0] } print f(%h), "\n";
