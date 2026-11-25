my %h=(k=>1); sub f { $h{k}=3; $_[0] } print f($h{k}), "\n";
