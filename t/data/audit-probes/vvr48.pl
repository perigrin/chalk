my @a = (1,2,3); sub md { shift @a; $_[0] } print md($a[1]), "\n";
