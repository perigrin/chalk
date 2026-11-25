our %h=(k=>1); sub f { local $h{k}=5; $_[0] } print f($h{k}), "\n";
