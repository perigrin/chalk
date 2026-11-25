my $x=1; sub f { @_ = reverse @_; "@_" } print f($x,2), "$x\n";
