my %h = (1=>1); sub f { $h{0+1} = 5; $_[0] } print f($h{1}), "\n";
