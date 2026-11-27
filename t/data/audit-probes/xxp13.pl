my @a = (1,2,3); sub cnt { scalar @_ } print cnt(@a[0,1] = (8,9)), "\n";
