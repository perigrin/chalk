my @a; sub f { $_[0]=1 } f($a[5]); print scalar(@a),"\n";
