our $x=0; sub f { $x=$_[0]; g2() } sub g2 { $x*2 } print f(3), f(4), "$x\n";
