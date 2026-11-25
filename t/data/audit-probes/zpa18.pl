my $x=1; sub f { my $r=\$_[0]; $$r=7 } f($x); print "$x\n";
