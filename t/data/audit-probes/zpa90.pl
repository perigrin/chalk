my $o={n=>1}; sub f { $_[0]=5 } f($o->{n}); print "$o->{n}\n";
