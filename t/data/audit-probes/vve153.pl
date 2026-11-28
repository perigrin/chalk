my %h = (k => 1); sub f { $_[0] = 9 } f(@h{qw(k)}); print $h{k}, "\n";
