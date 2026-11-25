my %h=(k=>1); sub f { $h{k}=9; my ($p)=@_; $p } print f($h{k}), "\n";
