my %h; sub f { $_[0]=1 } f($h{x}); print exists $h{x}?1:0,"\n";
