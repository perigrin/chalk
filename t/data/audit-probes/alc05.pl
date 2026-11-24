my $x=1; sub f { $x=2; "$_[0]$_[1]" } print f($x,$x),"\n";
