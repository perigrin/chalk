$_ = "x"; sub f { $_ = "y" } f(); print "$_\n";
