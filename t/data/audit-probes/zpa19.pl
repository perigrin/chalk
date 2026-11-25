my %h; sub f { 1 } f($h{k}); print exists $h{k} ? 1 : 0, "\n";
