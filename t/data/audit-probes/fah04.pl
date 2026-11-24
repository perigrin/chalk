our $x=1; sub f { my $o=$_[0]; $x=2; "$o$_[0]" } print f($x),"\n";
