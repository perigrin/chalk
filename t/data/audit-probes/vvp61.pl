my %h = (1=>1); sub f { $h{1.0} = 5; $_[0] } print f($h{1}), "\n";
