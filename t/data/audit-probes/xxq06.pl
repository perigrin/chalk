my @a = (1,2); for (@a) { undef $_ if $_ == 1 } print defined $a[0] ? "d" : "u", $a[1], "\n";
