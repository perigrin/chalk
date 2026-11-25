our $x = 1; sub g { print "$x\n" } sub f { local $x = 2; g(); print "$_[0]\n" } f($x);
