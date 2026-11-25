my $x=1; sub f { my $l = pop @_; scalar(@_) . $l } print f($x,2), "\n";
