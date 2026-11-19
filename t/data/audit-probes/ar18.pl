sub f { for (@_) { $_ = uc } } my ($x, @l) = ("a", "b", "c"); f($x, @l); print "$x @l\n";
