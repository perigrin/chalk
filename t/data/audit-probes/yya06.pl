my $x=1; sub f { my $p=$_[0]; $x=9; "$p$_[0]" } print f($x), "\n";
