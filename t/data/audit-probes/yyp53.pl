my $x=1; sub f { my $r=\$_[0]; my $p=$_[0]; $$r=9; $p } print f($x), "$x\n";
