my $x="ab"; sub f { $_[0] =~ tr/a/z/ } f($x); print "$x\n";
