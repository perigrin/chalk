my %h = (1=>1); sub f { $h{01} = 5; $_[0] } print f($h{1}), "\n";
