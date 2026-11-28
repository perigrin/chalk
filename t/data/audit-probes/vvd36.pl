my @a = (1,2,3); (@a[0,1], my $z) = @a[2,1,0]; print "@a$z\n";
