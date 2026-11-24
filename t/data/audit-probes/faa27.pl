my %h=(a=>1); sub f { $_[1]=0 } f(%h); print "$h{a}\n";
