sub f { my $o = $_[0]; $_[1]->(); "$o$_[0]" } my $x = 1; my @l = map { f($x, sub { $x += $_ }) } 1,2; print "@l\n";
