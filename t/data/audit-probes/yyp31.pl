my $x=1; sub f { @_=(); $_[0]=5; "@_" } print f($x), "$x\n";
