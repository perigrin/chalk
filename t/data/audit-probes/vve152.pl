my %h = (k => 1); sub f { $_[1] = 9 } f(%h); print $h{k}, "\n";
