my @a=(1,2); sub f { for my $x (@a) { $x.="!"; return 1 } } f(); print "@a\n";
