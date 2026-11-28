my %h = (k => 1); sub f { $_[0] = 9 } f(values %h); print $h{k}, "\n";
