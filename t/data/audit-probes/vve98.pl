my %h = (k=>1); sub f { $_ = 5 for values %h; $_[0] } print f($h{k}), "\n";
