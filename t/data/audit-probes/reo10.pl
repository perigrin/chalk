our $x=1; sub p { print "$x\n" } { local $x=2; p() } p();
