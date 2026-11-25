our $x=1; sub p { print $x } sub f { local $x=2; p(); { local $x=3; p() } p() } f(); p(); print "\n";
