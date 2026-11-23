my @a=(1,2); sub f { for my $e (@a) { $e .= "x"; return if $e eq "1x" } } f(); print "@a\n";
