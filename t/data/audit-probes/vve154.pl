my %h; sub f { $_[0] = 9 } f($h{new}); print exists $h{new} ? "e$h{new}" : "n", "\n";
