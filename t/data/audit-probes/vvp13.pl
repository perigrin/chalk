my @a = (1,2); sub f { $a[!1] = 5; $_[0] } { no warnings; print f($a[0]), "\n"; }
