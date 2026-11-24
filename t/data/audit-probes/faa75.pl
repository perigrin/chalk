sub tw { $_ *= 2 for @_ } my @a=(1,2); my $s=3; tw(@a,$s); print "@a $s\n";
