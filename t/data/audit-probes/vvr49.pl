my @a = (1,2,3); sub md { @a = reverse @a; $_[0] } print md($a[0]), "\n";
