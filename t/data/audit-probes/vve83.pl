my @a = (1,2); sub f { @a = (5,6); 0 } my $i = 0; print f($i), "@a\n";
