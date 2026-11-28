my @a = ("ab","c"); sub f { $a[-2] =~ s/a/z/; $_[0] } print f($a[0]), "\n";
