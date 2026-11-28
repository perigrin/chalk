my @a = (1,2); sub f { $a[-2] = 5; my @c = @_; $c[0] } print f($a[0]), "\n";
