my $x=1; sub f { $x=2; my $v=$_[0]; $v } print f($x+0), "\n";
