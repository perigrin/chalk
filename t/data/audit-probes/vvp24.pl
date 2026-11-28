my @a = (1,2); sub f { $a[-2] .= "x"; $_[0] } print f($a[0]), "\n";
