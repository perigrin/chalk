sub f { for (@_) { $_ *= 2 } } my @a=(1,2,3); my $z=4; f(@a,$z); print "@a $z\n";
