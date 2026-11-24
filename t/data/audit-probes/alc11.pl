my %h=(a=>1); sub f { $h{a}++; $_[0] * 10 } print f($h{a}),"\n";
