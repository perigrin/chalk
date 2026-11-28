my @a = (1,2); sub f { for ($a[-2]) { $_ = 5 } $_[0] } print f($a[0]), "\n";
