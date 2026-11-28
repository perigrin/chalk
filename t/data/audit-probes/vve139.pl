my ($x, $y); sub f { $_[0] = 9 } f($x // $y); print defined $x ? $x : "u", defined $y ? $y : "u", "\n";
