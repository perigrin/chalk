my $x=1; sub f { my $r=\$_[0]; $$r=9; my $p=$_[0]; $p } print f($x), "$x\n";
