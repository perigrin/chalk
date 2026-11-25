my %h=(a=>1); sub f { my %c=@_; $h{a}=9; $c{a} } print f(%h), "\n";
