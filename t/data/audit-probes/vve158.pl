my $r; sub f { $_[0] = 9 } f($r->{k}); print ref($r), $r->{k}, "\n";
