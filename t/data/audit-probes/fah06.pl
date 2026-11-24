my %h=(k=>1); sub f { $h{k}=2; $_[0] } print f($h{k}),"\n";
