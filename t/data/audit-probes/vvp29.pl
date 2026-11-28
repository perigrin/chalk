my @a = (1,2); sub f { my $o = $_[0]; $a[-2] = 5; "$o$_[0]" } print f($a[0]), "\n";
