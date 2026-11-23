our $g=1; sub f { local $g=2; die "x\n" } f() if 0; eval { f() }; eval { f() }; print "$g\n";
