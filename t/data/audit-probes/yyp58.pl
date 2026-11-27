my $x=1; sub g { $x++ } sub f { my $s=""; for my $i (1..2) { $s.=$_[0]; g() } $s } print f($x), "$x\n";
