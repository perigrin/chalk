sub f { my ($p,$q)=@_; defined $q ? "d" : "u" } print f(1), f(1,2), f(1,undef), "\n";
