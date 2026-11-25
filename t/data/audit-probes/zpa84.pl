my $x=1; sub f { my $v=\shift; $$v++ } f($x); print "$x\n";
