my @a=(1,2); sub z { $_[0]=7 } print map { z($_); $_ } @a; print " @a\n";
