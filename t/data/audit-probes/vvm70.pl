our $x = 1; sub f :lvalue { $x } f() = 3; { local $x = 2; } f() += 1; print "$x\n";
