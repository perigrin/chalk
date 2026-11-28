our $x = 1; sub f :lvalue { $x } f() = 5; print "$x\n";
