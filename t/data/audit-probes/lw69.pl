my @a=(1,2); sub f { for (@a) { $_ .= "x"; return if $_ eq "1x" } } f(); print "@a\n";
