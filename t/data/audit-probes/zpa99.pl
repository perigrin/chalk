my @a=(1,2); sub cnt { scalar @_ } sub f { $#_=0; cnt(@_) } print f(@a),"@a\n";
