our $x = 1; sub f { local $x = 2; print "$_[0]\n" } f($x);
