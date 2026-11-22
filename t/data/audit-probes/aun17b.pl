my @l = (1,2); for (@l) { my $o = $_; inner(); print "$o$_ " } sub inner { $_ = 9 } print "@l\n";
