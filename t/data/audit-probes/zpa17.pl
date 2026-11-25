my ($x,$y)=(1,2); sub f { for (@_) { $_++ } } f($x,$y); print "$x$y\n";
