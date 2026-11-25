my %h=(k=>1); sub f { my ($p)=@_; delete $h{k}; $p } print f($h{k}), "\n";
