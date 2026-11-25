our $x=1; sub f { local $x=5; $_[0]=7; $x } print f($x),$x,"\n";
